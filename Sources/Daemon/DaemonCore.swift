import Foundation

protocol SystemBlocker {
    func apply(spec: EffectiveBlockingSpec, killExistingConnections: Bool) throws
    func verifyHostsIntegrity(for spec: EffectiveBlockingSpec) -> Bool
}

final class DaemonCore {
    private let queue = DispatchQueue(label: "com.santiagodetuna.huerequeque-zen.core")
    private let stateURL: URL
    private let blocker: SystemBlocker
    private let clock: () -> Date
    private let calendar: Calendar
    private(set) var state: DaemonState
    private var lastAppliedSpec: EffectiveBlockingSpec?
    private var lastPersistDuringWindow: Date = .distantPast

    init(
        stateURL: URL = URL(fileURLWithPath: ZenConstants.stateFilePath),
        blocker: SystemBlocker,
        clock: @escaping () -> Date = Date.init,
        calendar: Calendar = .current
    ) {
        self.stateURL = stateURL
        self.blocker = blocker
        self.clock = clock
        self.calendar = calendar

        let now = clock()
        if let loaded = Self.loadState(from: stateURL) {
            var s = loaded
            s.daemonVersion = ZenConstants.daemonVersion
            self.state = s
        } else {
            self.state = DaemonState.initial(now: now, calendar: calendar)
        }
    }

    private static func loadState(from url: URL) -> DaemonState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? SocketJSON.decoder().decode(DaemonState.self, from: data)
    }

    /// Call on daemon startup to immediately re-apply any active block or Allowtime guard (reboot-proof).
    func bootstrapEnforcement() {
        queue.sync {
            let now = clock()
            reconcileExpirationsLocked(now: now)
            enforceLocked(now: now, force: true, killExisting: true)
            persistLocked()
        }
    }

    /// Called every 1 second by the daemon timer.
    func tick(checkIntegrity: Bool = false, forceIPRefresh: Bool = false) {
        queue.sync {
            let now = clock()
            let changed = reconcileExpirationsLocked(now: now)
            let spec = state.effectiveBlockingSpec(at: now)

            if changed || forceIPRefresh || lastAppliedSpec != spec {
                let kill = changed || (lastAppliedSpec != spec && spec.isBlockingAnything)
                enforceLocked(now: now, force: true, killExisting: kill)
                persistLocked()
            } else if checkIntegrity && spec.isBlockingAnything {
                if !blocker.verifyHostsIntegrity(for: spec) {
                    enforceLocked(now: now, force: true, killExisting: false)
                }
            }

            // Periodically checkpoint while Allowtime window is open so sudden reboot preserves accurate usage.
            if state.isAllowtimeWindowOpen(at: now),
               now.timeIntervalSince(lastPersistDuringWindow) >= 30 {
                persistLocked()
                lastPersistDuringWindow = now
            }
        }
    }

    func handle(_ request: DaemonRequest) -> DaemonResponse {
        queue.sync {
            let now = clock()
            let expired = reconcileExpirationsLocked(now: now)
            if expired {
                enforceLocked(now: now, force: true, killExisting: true)
                persistLocked()
            }

            switch request.command {
            case .ping:
                return DaemonResponse(ok: true, message: nil, state: state)

            case .startBlock:
                return handleStartBlockLocked(request, now: now)

            case .extendBlock:
                return handleExtendBlockLocked(request, now: now)

            case .addBlockDomains:
                return handleAddBlockDomainsLocked(request, now: now)

            case .updateAllowtimeConfig:
                return handleUpdateAllowtimeLocked(request, now: now)

            case .openAllowtimeWindow:
                return handleOpenAllowtimeWindowLocked(request, now: now)

            case .closeAllowtimeWindow:
                return handleCloseAllowtimeWindowLocked(now: now)
            }
        }
    }

    // MARK: - Command Handlers (All Unbreakable Invariants Live Here)

    private func handleStartBlockLocked(_ request: DaemonRequest, now: Date) -> DaemonResponse {
        if state.isBlockActive(at: now) {
            return DaemonResponse(ok: false, message: "Ya hay un bloqueo activo. Solo puedes extenderlo o sumar sitios.", state: state)
        }

        let mode = request.mode ?? .blocklist
        let domains = DomainNormalizer.normalizeList(request.domains ?? [])
        guard !domains.isEmpty else {
            return DaemonResponse(ok: false, message: "Agrega al menos un dominio válido antes de bloquear.", state: state)
        }

        let duration = request.durationSeconds ?? 0
        guard duration >= ZenConstants.minBlockSeconds, duration <= ZenConstants.maxBlockSeconds else {
            return DaemonResponse(ok: false, message: "La duración debe estar entre 1 minuto y 24 horas.", state: state)
        }

        // If an Allowtime window is currently open and the new On-Demand block covers all Allowtime domains, close the window cleanly!
        let endsAt = now.addingTimeInterval(TimeInterval(duration))
        let newBlock = ActiveBlock(
            id: UUID().uuidString,
            mode: mode,
            domains: domains,
            startedAt: now,
            endsAt: endsAt,
            label: request.label
        )
        state.activeBlock = newBlock

        if state.isAllowtimeWindowOpen(at: now) && state.allowtimeDomainsBlockedByOnDemand(at: now) {
            closeActiveAllowtimeWindowLocked(now: now)
        }

        enforceLocked(now: now, force: true, killExisting: true)
        persistLocked()
        return DaemonResponse(ok: true, message: "Bloqueo irrompible iniciado.", state: state)
    }

    private func handleExtendBlockLocked(_ request: DaemonRequest, now: Date) -> DaemonResponse {
        guard var block = state.activeBlock, block.endsAt > now else {
            return DaemonResponse(ok: false, message: "No hay un bloqueo activo para extender.", state: state)
        }
        let add = request.durationSeconds ?? 0
        guard add > 0 else {
            return DaemonResponse(ok: false, message: "Solo se puede sumar tiempo, nunca restar.", state: state)
        }
        let clampedAdd = min(add, ZenConstants.maxExtendSeconds)
        let candidateEnd = block.endsAt.addingTimeInterval(TimeInterval(clampedAdd))
        let maxEnd = now.addingTimeInterval(TimeInterval(ZenConstants.maxBlockSeconds))
        let newEnd = min(candidateEnd, maxEnd)
        guard newEnd > block.endsAt else {
            return DaemonResponse(ok: false, message: "Ya alcanzaste el límite máximo de 24 horas.", state: state)
        }

        block.endsAt = newEnd
        state.activeBlock = block
        persistLocked()
        return DaemonResponse(ok: true, message: "Bloqueo extendido.", state: state)
    }

    private func handleAddBlockDomainsLocked(_ request: DaemonRequest, now: Date) -> DaemonResponse {
        guard var block = state.activeBlock, block.endsAt > now else {
            return DaemonResponse(ok: false, message: "No hay un bloqueo activo.", state: state)
        }
        guard block.mode == .blocklist else {
            return DaemonResponse(ok: false, message: "En modo Solo permitir no se puede cambiar la lista durante el bloqueo.", state: state)
        }
        let incoming = DomainNormalizer.normalizeList(request.domains ?? [])
        guard !incoming.isEmpty else {
            return DaemonResponse(ok: false, message: "No se encontraron dominios válidos para agregar.", state: state)
        }
        let merged = DomainNormalizer.normalizeList(block.domains + incoming)
        guard merged.count > block.domains.count else {
            return DaemonResponse(ok: true, message: "Esos dominios ya estaban bloqueados.", state: state)
        }

        block.domains = merged
        state.activeBlock = block
        enforceLocked(now: now, force: true, killExisting: true)
        persistLocked()
        return DaemonResponse(ok: true, message: "Dominios sumados al bloqueo.", state: state)
    }

    private func handleUpdateAllowtimeLocked(_ request: DaemonRequest, now: Date) -> DaemonResponse {
        guard var incoming = request.allowtimeConfig else {
            return DaemonResponse(ok: false, message: "Falta la configuración de Allowtime.", state: state)
        }
        incoming.domains = DomainNormalizer.normalizeList(incoming.domains)
        incoming.dailyBudgetSeconds = max(0, min(incoming.dailyBudgetSeconds, 12 * 3600))
        incoming.defaultWindowSeconds = max(ZenConstants.minAllowtimeWindowSeconds, min(incoming.defaultWindowSeconds, ZenConstants.maxAllowtimeWindowSeconds))

        let current = state.allowtimeConfig
        let today = DaemonState.dayKey(for: now, calendar: calendar)
        let blockActive = state.isBlockActive(at: now)
        let strictLocked = state.isStrictDailyLockActive(at: now, calendar: calendar)

        if blockActive || strictLocked {
            let lockReason = blockActive
                ? "No puedes aflojar Allowtime mientras haya un bloqueo irrompible activo."
                : "El candado diario de Allowtime está activo hasta mañana."

            // Cannot disable Allowtime while locked
            if current.enabled && !incoming.enabled {
                return DaemonResponse(ok: false, message: lockReason, state: state)
            }
            // Cannot remove existing Allowtime domains while locked
            let incomingSet = Set(incoming.domains)
            if current.enabled && current.domains.contains(where: { !incomingSet.contains($0) }) {
                return DaemonResponse(ok: false, message: lockReason, state: state)
            }
            // Cannot increase daily budget (or switch from finite budget to unlimited 0) while locked
            if current.enabled && current.dailyBudgetSeconds > 0 {
                if incoming.dailyBudgetSeconds == 0 || incoming.dailyBudgetSeconds > current.dailyBudgetSeconds {
                    return DaemonResponse(ok: false, message: lockReason, state: state)
                }
            }
            // Cannot disable strictDailyLock once armed for today
            if strictLocked && !incoming.strictDailyLock {
                return DaemonResponse(ok: false, message: lockReason, state: state)
            }
        }

        // If Allowtime is being disabled (when permitted), close any open window first
        if !incoming.enabled && state.isAllowtimeWindowOpen(at: now) {
            closeActiveAllowtimeWindowLocked(now: now)
        }

        state.allowtimeConfig = incoming
        if incoming.enabled && incoming.strictDailyLock {
            state.allowtimeRuntime.lockedDayKey = today
        } else if !incoming.strictDailyLock && !strictLocked {
            state.allowtimeRuntime.lockedDayKey = nil
        }

        enforceLocked(now: now, force: true, killExisting: true)
        persistLocked()
        return DaemonResponse(ok: true, message: "Allowtime actualizado.", state: state)
    }

    private func handleOpenAllowtimeWindowLocked(_ request: DaemonRequest, now: Date) -> DaemonResponse {
        let check = state.canOpenAllowtimeWindow(at: now, calendar: calendar)
        switch check {
        case .unavailable(let reason):
            return DaemonResponse(ok: false, message: reason, state: state)
        case .allowed(let maxGrantSeconds):
            let requested = request.durationSeconds ?? state.allowtimeConfig.defaultWindowSeconds
            let clamped = max(ZenConstants.minAllowtimeWindowSeconds, min(requested, maxGrantSeconds))
            let today = DaemonState.dayKey(for: now, calendar: calendar)
            if state.allowtimeRuntime.dayKey != today {
                state.allowtimeRuntime.dayKey = today
                state.allowtimeRuntime.usedTodaySeconds = 0
            }
            state.allowtimeRuntime.windowStartedAt = now
            state.allowtimeRuntime.windowEndsAt = now.addingTimeInterval(TimeInterval(clamped))
            lastPersistDuringWindow = now

            enforceLocked(now: now, force: true, killExisting: false)
            persistLocked()
            return DaemonResponse(ok: true, message: "Ventana Allowtime abierta.", state: state)
        }
    }

    private func handleCloseAllowtimeWindowLocked(now: Date) -> DaemonResponse {
        guard state.isAllowtimeWindowOpen(at: now) else {
            return DaemonResponse(ok: true, message: "La ventana ya estaba cerrada.", state: state)
        }
        closeActiveAllowtimeWindowLocked(now: now)
        enforceLocked(now: now, force: true, killExisting: true)
        persistLocked()
        return DaemonResponse(ok: true, message: "Ventana cerrada. Sitios bloqueados de nuevo.", state: state)
    }

    // MARK: - Reconciliation & Persistence

    @discardableResult
    private func reconcileExpirationsLocked(now: Date) -> Bool {
        var changed = false
        let today = DaemonState.dayKey(for: now, calendar: calendar)

        // 1. Check active On-Demand block expiration
        if let block = state.activeBlock, now >= block.endsAt {
            state.activeBlock = nil
            changed = true
        }

        // 2. Check Allowtime window expiration BEFORE rolling day key so elapsed time is counted cleanly
        if let start = state.allowtimeRuntime.windowStartedAt,
           let end = state.allowtimeRuntime.windowEndsAt,
           now >= end {
            let elapsed = max(0, Int(end.timeIntervalSince(start)))
            if state.allowtimeRuntime.dayKey == today {
                state.allowtimeRuntime.usedTodaySeconds += elapsed
            }
            state.allowtimeRuntime.windowStartedAt = nil
            state.allowtimeRuntime.windowEndsAt = nil
            changed = true
        }

        // 3. Rollover calendar day for daily Allowtime budget and strict daily lock
        if state.allowtimeRuntime.dayKey != today {
            state.allowtimeRuntime.dayKey = today
            state.allowtimeRuntime.usedTodaySeconds = 0
            if let lockedDay = state.allowtimeRuntime.lockedDayKey, lockedDay != today {
                state.allowtimeRuntime.lockedDayKey = nil
                if state.allowtimeConfig.strictDailyLock && state.allowtimeConfig.enabled {
                    // Reset strict lock at midnight so user gets a deliberate fresh day choice (or re-arm cleanly)
                    state.allowtimeConfig.strictDailyLock = false
                }
            }
            changed = true
        }

        return changed
    }

    private func closeActiveAllowtimeWindowLocked(now: Date) {
        if let start = state.allowtimeRuntime.windowStartedAt {
            let end = state.allowtimeRuntime.windowEndsAt ?? now
            let effectiveEnd = min(now, end)
            let elapsed = max(0, Int(effectiveEnd.timeIntervalSince(start)))
            let today = DaemonState.dayKey(for: now, calendar: calendar)
            if state.allowtimeRuntime.dayKey != today {
                state.allowtimeRuntime.dayKey = today
                state.allowtimeRuntime.usedTodaySeconds = 0
            }
            state.allowtimeRuntime.usedTodaySeconds += elapsed
        }
        state.allowtimeRuntime.windowStartedAt = nil
        state.allowtimeRuntime.windowEndsAt = nil
    }

    private func enforceLocked(now: Date, force: Bool, killExisting: Bool) {
        let spec = state.effectiveBlockingSpec(at: now)
        if !force && lastAppliedSpec == spec { return }
        do {
            try blocker.apply(spec: spec, killExistingConnections: killExisting)
            lastAppliedSpec = spec
            state.lastEnforcedAt = now
            state.lastError = nil
        } catch {
            state.lastError = error.localizedDescription
        }
    }

    private func persistLocked() {
        let dir = stateURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? SocketJSON.encoder().encode(state) else { return }
        let tmp = dir.appendingPathComponent(".state.\(UUID().uuidString).tmp")
        do {
            try data.write(to: tmp, options: .atomic)
            chmod(tmp.path, 0o644)
            _ = try? FileManager.default.replaceItemAt(stateURL, withItemAt: tmp)
            if !FileManager.default.fileExists(atPath: stateURL.path) {
                try FileManager.default.moveItem(at: tmp, to: stateURL)
            }
            chmod(stateURL.path, 0o644)
        } catch {
            try? FileManager.default.removeItem(at: tmp)
        }
    }
}
