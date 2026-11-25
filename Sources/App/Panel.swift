import AppKit
import SwiftUI

struct Panel: View {
    @ObservedObject var store: ZenStore
    @State private var newProfileDomain = ""
    @State private var newLockedDomain = ""
    @State private var newAllowtimeDomain = ""
    @State private var hoveredDomain: String?
    @State private var showAbout = false

    private let blockPresets = [25, 45, 60, 120, 240]
    private let windowPresets = [5, 10, 15, 30]
    private let budgetOptions = [15, 30, 45, 60, 0]

    var body: some View {
        ZStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 12) {
                header
                modeSwitcher
                if !store.daemonConnected {
                    daemonBanner
                }
                if store.selectedTab == .block {
                    blockView
                } else {
                    allowtimeView
                }
            }
            .padding(16)
            .frame(width: 414)
            .background(LlamaTheme.bg)
            .foregroundColor(LlamaTheme.ink)
            .tint(LlamaTheme.accent)

            if let toast = store.toast {
                toastPill(toast)
                    .padding(.top, 10)
                    .transition(.opacity)
                    .zIndex(50)
            }
        }
        .popover(isPresented: $showAbout) { aboutPopover }
        .background(keyboardShortcuts)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            if let image = Bundle.main.image(forResource: "Huerequeque") {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 46, height: 46)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text("Huerequeque Zen")
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                        .accessibilityAddTraits(.isHeader)
                    Menu {
                        Button("Importar lista de SelfControl") {
                            if store.selectedTab == .block {
                                store.importSelfControlIntoProfile()
                            } else {
                                store.importSelfControlIntoAllowtime()
                            }
                        }
                        .disabled(store.selfControlDomains.isEmpty)

                        Button(store.daemonConnected ? "Reinstalar guardián irrompible" : "Instalar guardián irrompible") {
                            store.installDaemon()
                        }

                        Menu("Apariencia") {
                            ForEach(AppearancePreference.allCases, id: \.self) { pref in
                                Button {
                                    store.setAppearance(pref)
                                } label: {
                                    if store.appearance == pref {
                                        Label(pref.title, systemImage: "checkmark")
                                    } else {
                                        Text(pref.title)
                                    }
                                }
                            }
                        }

                        Divider()
                        Button("Acerca de Huerequeque Zen") { showAbout = true }
                        Divider()
                        Button("Salir de Huerequeque Zen") { store.quitApp() }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(LlamaTheme.ink2)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .frame(width: 20, height: 22)
                    .help("Opciones de Huerequeque Zen")
                    .accessibilityLabel("Opciones de Huerequeque Zen")
                }

                Text(headerSubtitle)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(headerSubtitleColor)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            statusBadge
        }
    }

    private var headerSubtitle: String {
        let now = store.now
        if store.daemonState.isBlockActive(at: now) {
            let count = store.daemonState.activeBlock?.domains.count ?? 0
            return "Bloqueo irrompible · \(count) sitios"
        }
        if store.daemonState.isAllowtimeWindowOpen(at: now) {
            let rem = ZenFormat.countdown(store.daemonState.allowtimeWindowRemainingSeconds(at: now))
            return "Ventana Allowtime · \(rem)"
        }
        if store.daemonState.isAllowtimeGuarding(at: now) {
            let count = store.daemonState.allowtimeConfig.domains.count
            return "Allowtime en guardia · \(count) sitios"
        }
        if !store.daemonConnected {
            return "Guardián sin activar"
        }
        return "En calma · sin bloqueos"
    }

    private var headerSubtitleColor: Color {
        let now = store.now
        if store.daemonState.isBlockActive(at: now) { return LlamaTheme.accentInk }
        if store.daemonState.isAllowtimeWindowOpen(at: now) { return LlamaTheme.warnInk }
        if store.daemonState.isAllowtimeGuarding(at: now) { return LlamaTheme.okInk }
        if !store.daemonConnected { return LlamaTheme.warnInk }
        return LlamaTheme.muted
    }

    private var statusBadge: some View {
        let now = store.now
        let text: String
        let bg: Color
        let fg: Color
        if store.daemonState.isBlockActive(at: now) {
            text = "Irrompible"
            bg = LlamaTheme.accentSoft
            fg = LlamaTheme.accentInk
        } else if store.daemonState.isAllowtimeWindowOpen(at: now) {
            text = "Ventana"
            bg = LlamaTheme.warnSoft
            fg = LlamaTheme.warnInk
        } else if store.daemonState.isAllowtimeGuarding(at: now) {
            text = "Guardia"
            bg = LlamaTheme.okSoft
            fg = LlamaTheme.okInk
        } else {
            text = "En calma"
            bg = LlamaTheme.graySoft
            fg = LlamaTheme.grayInk
        }

        return Text(text)
            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .foregroundColor(fg)
            .background(Capsule().fill(bg))
    }

    // MARK: - Mode Switcher

    private var modeSwitcher: some View {
        HStack(spacing: 4) {
            ForEach(ZenTab.allCases, id: \.self) { tab in
                let selected = (store.selectedTab == tab)
                Button {
                    store.selectedTab = tab
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tab == .block ? "lock.shield" : "hourglass")
                            .font(.system(size: 12, weight: .semibold))
                        Text(tab.title)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                        if tab == .allowtime && store.daemonState.isAllowtimeWindowOpen(at: store.now) {
                            Circle()
                                .fill(LlamaTheme.warn)
                                .frame(width: 6, height: 6)
                        } else if tab == .block && store.daemonState.isBlockActive(at: store.now) {
                            Circle()
                                .fill(LlamaTheme.accent)
                                .frame(width: 6, height: 6)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .foregroundColor(selected ? LlamaTheme.ink : LlamaTheme.muted)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(selected ? LlamaTheme.surface : Color.clear)
                            .shadow(color: selected ? .black.opacity(0.06) : .clear, radius: 1, y: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(LlamaTheme.fill))
    }

    // MARK: - Daemon Setup Banner

    private var daemonBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "shield.lefthalf.filled.badge.checkmark")
                .font(.system(size: 18))
                .foregroundColor(LlamaTheme.warnInk)
            VStack(alignment: .leading, spacing: 2) {
                Text("Activa el guardián irrompible")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(LlamaTheme.ink)
                Text("Se instala 1 vez con clave admin. Sobrevive reinicios.")
                    .font(.system(size: 11))
                    .foregroundColor(LlamaTheme.muted)
            }
            Spacer(minLength: 4)
            Button {
                store.installDaemon()
            } label: {
                Text(store.isInstallingDaemon ? "Activando..." : "Activar")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .foregroundColor(LlamaTheme.accentOn)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(LlamaTheme.accent))
            }
            .buttonStyle(.plain)
            .disabled(store.isInstallingDaemon)
        }
        .padding(11)
        .background(RoundedRectangle(cornerRadius: LlamaTheme.radioLista, style: .continuous).fill(LlamaTheme.warnSoft))
    }

    // MARK: - Tab 1: Bloqueo On-Demand

    private var blockView: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let active = store.daemonState.activeBlock, store.daemonState.isBlockActive(at: store.now) {
                lockedHeroCard(active)
            } else {
                idleBlockHeroCard
            }
            profileDomainsCard
        }
    }

    private var idleBlockHeroCard: some View {
        let durSec = store.effectiveDurationSeconds
        let endDate = store.now.addingTimeInterval(TimeInterval(durSec))
        let dialProgress = min(1.0, Double(durSec) / Double(4 * 3600))
        let profile = store.activeProfile

        return VStack(spacing: 12) {
            HStack(spacing: 14) {
                ZenLockDial(
                    progress: max(0.08, dialProgress),
                    primaryText: ZenFormat.durationLabel(minutes: max(1, durSec / 60)),
                    secondaryText: "Hasta las \(ZenFormat.endClockString(from: endDate))",
                    tint: LlamaTheme.accent,
                    tintInk: LlamaTheme.accentInk,
                    isLocked: false
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text("Duración")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(LlamaTheme.muted)

                    // Quick duration chips
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                        ForEach(blockPresets, id: \.self) { mins in
                            let picked = !store.useUntilTime && store.durationMinutes == mins
                            Button {
                                store.setDurationMinutes(mins)
                            } label: {
                                Text(mins >= 60 ? "\(mins / 60) h" : "\(mins)m")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 5)
                                    .foregroundColor(picked ? LlamaTheme.accentInk : LlamaTheme.ink2)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(picked ? LlamaTheme.accentSoft : LlamaTheme.fill)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                        Button {
                            store.useUntilTime.toggle()
                            if store.useUntilTime {
                                store.untilDate = store.now.addingTimeInterval(TimeInterval(store.durationMinutes * 60))
                            }
                        } label: {
                            Text("Hora")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 5)
                                .foregroundColor(store.useUntilTime ? LlamaTheme.accentInk : LlamaTheme.ink2)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(store.useUntilTime ? LlamaTheme.accentSoft : LlamaTheme.fill)
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    if store.useUntilTime {
                        DatePicker("Hasta", selection: $store.untilDate, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .controlSize(.small)
                    } else {
                        Slider(
                            value: Binding(
                                get: { Double(min(store.durationMinutes, 480)) },
                                set: { store.setDurationMinutes(Int(($0 / 5).rounded()) * 5) }
                            ),
                            in: 5...480,
                            step: 5
                        )
                        .controlSize(.small)
                    }

                    // Blocklist vs Allowlist toggle
                    HStack(spacing: 4) {
                        ForEach(BlockMode.allCases, id: \.self) { mode in
                            let selected = profile.mode == mode
                            Button {
                                store.setProfileMode(mode)
                            } label: {
                                Text(mode.shortLabel)
                                    .font(.system(size: 11, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 4)
                                    .foregroundColor(selected ? LlamaTheme.accentInk : LlamaTheme.muted)
                                    .background(
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .fill(selected ? LlamaTheme.accentSoft : Color.clear)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(2)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(LlamaTheme.fill))
                }
            }

            Button { store.startOnDemandBlock() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 13, weight: .bold))
                    Text(startBlockButtonLabel)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 38)
            }
            .buttonStyle(PrimaryZenButtonStyle(tint: LlamaTheme.accent))
            .disabled(!store.daemonConnected || profile.domains.isEmpty)
        }
        .padding(14)
        .llamaSurface()
    }

    private var startBlockButtonLabel: String {
        let count = store.activeProfile.domains.count
        let dur = ZenFormat.durationLabel(minutes: max(1, store.effectiveDurationSeconds / 60))
        if store.activeProfile.mode == .allowlist {
            return "Solo permitir \(count) sitios · \(dur)"
        }
        return "Bloquear \(count) sitios · \(dur)"
    }

    private func lockedHeroCard(_ block: ActiveBlock) -> some View {
        let total = max(1, block.endsAt.timeIntervalSince(block.startedAt))
        let rem = max(0, block.endsAt.timeIntervalSince(store.now))
        let progress = rem / total

        return VStack(spacing: 12) {
            HStack(spacing: 14) {
                ZenLockDial(
                    progress: progress,
                    primaryText: ZenFormat.countdown(Int(ceil(rem))),
                    secondaryText: "Hasta las \(ZenFormat.endClockString(from: block.endsAt))",
                    tint: LlamaTheme.accent,
                    tintInk: LlamaTheme.accentInk,
                    isLocked: true
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text(block.mode == .allowlist ? "Solo permitidos activos" : "Bloqueo irrompible")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                    Text("No se puede cancelar ni cerrando la app o reiniciando.")
                        .font(.system(size: 11.5))
                        .foregroundColor(LlamaTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Extender tiempo")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(LlamaTheme.muted)
                        .padding(.top, 2)

                    HStack(spacing: 6) {
                        ForEach([15, 30, 60], id: \.self) { mins in
                            Button {
                                store.extendActiveBlock(minutes: mins)
                            } label: {
                                Text(mins == 60 ? "+1 h" : "+\(mins)m")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 5)
                                    .foregroundColor(LlamaTheme.accentInk)
                                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(LlamaTheme.accentSoft))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if block.mode == .blocklist {
                HStack(spacing: 8) {
                    TextField("Sumar otro sitio al bloqueo (ej. reddit.com)", text: $newLockedDomain)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(LlamaTheme.fill))
                        .onSubmit {
                            let val = newLockedDomain
                            newLockedDomain = ""
                            store.addDomainsToActiveBlock(val)
                        }
                    Button("Sumar") {
                        let val = newLockedDomain
                        newLockedDomain = ""
                        store.addDomainsToActiveBlock(val)
                    }
                    .buttonStyle(SecondaryZenButtonStyle())
                    .disabled(newLockedDomain.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .padding(14)
        .llamaSurface()
    }

    private var profileDomainsCard: some View {
        let isLocked = store.daemonState.isBlockActive(at: store.now)
        let domainsToShow = isLocked ? (store.daemonState.activeBlock?.domains ?? []) : store.activeProfile.domains

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                if !isLocked {
                    ForEach(store.profiles) { profile in
                        let selected = profile.id == store.selectedProfileID
                        Button {
                            store.selectProfile(profile.id)
                        } label: {
                            Text(profile.name)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .foregroundColor(selected ? LlamaTheme.accentInk : LlamaTheme.muted)
                                .background(Capsule().fill(selected ? LlamaTheme.accentSoft : LlamaTheme.fill))
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    Text("Sitios bajo bloqueo (\(domainsToShow.count))")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                }
                Spacer()
                if !isLocked && !store.unimportedSelfControlDomainsForProfile.isEmpty {
                    Button {
                        store.importSelfControlIntoProfile()
                    } label: {
                        Label("SelfControl", systemImage: "square.and.arrow.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(LlamaTheme.accentInk)
                    }
                    .buttonStyle(.plain)
                    .help("Importar tus dominios guardados en SelfControl")
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)

            if !isLocked {
                HStack(spacing: 8) {
                    TextField("Agregar dominio (x.com, youtube.com...)", text: $newProfileDomain)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(LlamaTheme.fill))
                        .onSubmit {
                            let val = newProfileDomain
                            newProfileDomain = ""
                            store.addDomainsToProfile(val)
                        }
                    Button("Agregar") {
                        let val = newProfileDomain
                        newProfileDomain = ""
                        store.addDomainsToProfile(val)
                    }
                    .buttonStyle(SecondaryZenButtonStyle())
                    .disabled(newProfileDomain.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.horizontal, 14)
            }

            domainList(domains: domainsToShow, removable: !isLocked) { domain in
                store.removeDomainFromProfile(domain)
            }
        }
        .padding(.bottom, 8)
        .llamaSurface()
    }

    // MARK: - Tab 2: Allowtime (Extra distractorios)

    private var allowtimeView: some View {
        let cfg = store.daemonState.allowtimeConfig
        let now = store.now
        let isOpen = store.daemonState.isAllowtimeWindowOpen(at: now)
        let usedSec = store.daemonState.effectiveAllowtimeUsedToday(at: now)
        let openCheck = store.daemonState.canOpenAllowtimeWindow(at: now)
        let isStrictLocked = store.daemonState.isStrictDailyLockActive(at: now) || store.daemonState.isBlockActive(at: now)

        return VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 12) {
                // Top Allowtime Arm Switch
                HStack(spacing: 10) {
                    Image(systemName: cfg.enabled ? "shield.checkered" : "shield.slash")
                        .font(.system(size: 16))
                        .foregroundColor(cfg.enabled ? (isOpen ? LlamaTheme.warnInk : LlamaTheme.okInk) : LlamaTheme.muted)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Guardia Allowtime")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                        Text(cfg.enabled ? "Siempre bloqueados, salvo en tu ventana." : "Apagada. Actívala para bloquear 24/7.")
                            .font(.system(size: 11))
                            .foregroundColor(LlamaTheme.muted)
                    }
                    Spacer()
                    if cfg.enabled && isStrictLocked {
                        Label("Activa", systemImage: "lock.fill")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .foregroundColor(LlamaTheme.accentInk)
                            .background(Capsule().fill(LlamaTheme.accentSoft))
                            .help("Bloqueada hasta mañana por Candado diario o bloqueo activo.")
                    } else {
                        Toggle("Guardia Allowtime", isOn: Binding(
                            get: { cfg.enabled },
                            set: { store.setAllowtimeEnabled($0) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    }
                }

                Rectangle().fill(LlamaTheme.line.opacity(0.5)).frame(height: 0.5)

                // Signature Allowtime Dial + Controls
                if isOpen {
                    let rem = store.daemonState.allowtimeWindowRemainingSeconds(at: now)
                    let total = max(1, Int((store.daemonState.allowtimeRuntime.windowEndsAt ?? now).timeIntervalSince(store.daemonState.allowtimeRuntime.windowStartedAt ?? now)))
                    HStack(spacing: 14) {
                        ZenLockDial(
                            progress: Double(rem) / Double(total),
                            primaryText: ZenFormat.countdown(rem),
                            secondaryText: "Se cierra solo",
                            tint: LlamaTheme.warn,
                            tintInk: LlamaTheme.warnInk,
                            isLocked: false
                        )
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Ventana abierta")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundColor(LlamaTheme.warnInk)
                            Text("Al terminar el contador, el guardián vuelve a bloquear estos sitios automáticamente.")
                                .font(.system(size: 11.5))
                                .foregroundColor(LlamaTheme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                            Button { store.closeAllowtimeWindow() } label: {
                                Label("Cerrar ventana ya", systemImage: "lock.fill")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 34)
                            }
                            .buttonStyle(PrimaryZenButtonStyle(tint: LlamaTheme.ok))
                        }
                    }
                } else {
                    VStack(spacing: 10) {
                        HStack(spacing: 6) {
                            Text("Ventana")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(LlamaTheme.muted)
                            Spacer()
                            ForEach(windowPresets, id: \.self) { mins in
                                let picked = store.selectedWindowMinutes == mins
                                Button {
                                    store.setSelectedWindowMinutes(mins)
                                } label: {
                                    Text("\(mins)m")
                                        .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .foregroundColor(picked ? LlamaTheme.accentInk : LlamaTheme.ink2)
                                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(picked ? LlamaTheme.accentSoft : LlamaTheme.fill))
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Button { store.openAllowtimeWindow() } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "lock.open.fill")
                                    .font(.system(size: 12.5, weight: .bold))
                                Text("Abrir ventana · \(store.selectedWindowMinutes) min")
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                        }
                        .buttonStyle(PrimaryZenButtonStyle(tint: LlamaTheme.accent))
                        .disabled(!store.daemonConnected || {
                            if case .allowed = openCheck { return false }
                            return true
                        }())

                        if case .unavailable(let reason) = openCheck, cfg.enabled {
                            Text(reason)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundColor(LlamaTheme.warnInk)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }

                Rectangle().fill(LlamaTheme.line.opacity(0.5)).frame(height: 0.5)

                // Segmented Daily Budget Bar + Quick Picker
                AllowtimeBudgetBar(
                    usedSeconds: usedSec,
                    budgetSeconds: cfg.dailyBudgetSeconds,
                    isWindowOpen: isOpen
                )

                HStack(spacing: 5) {
                    Text("Límite diario")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(LlamaTheme.muted)
                    Spacer()
                    ForEach(budgetOptions, id: \.self) { mins in
                        let selected = cfg.dailyBudgetSeconds == mins * 60
                        let wouldLoosen = cfg.enabled && isStrictLocked && cfg.dailyBudgetSeconds > 0 && (mins == 0 || mins * 60 > cfg.dailyBudgetSeconds)
                        Button {
                            store.setAllowtimeDailyBudget(minutes: mins)
                        } label: {
                            Text(mins == 0 ? "Libre" : "\(mins)m")
                                .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .foregroundColor(selected ? LlamaTheme.accentInk : LlamaTheme.muted)
                                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(selected ? LlamaTheme.accentSoft : LlamaTheme.fill))
                        }
                        .buttonStyle(.plain)
                        .disabled(wouldLoosen)
                        .opacity(wouldLoosen ? 0.45 : 1)
                    }
                }
            }
            .padding(14)
            .llamaSurface()

            // Allowtime Domains & Strict Daily Lock Card
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Sitios Allowtime (\(cfg.domains.count))")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                    Spacer()
                    if !store.unimportedSelfControlDomainsForAllowtime.isEmpty {
                        Button {
                            store.importSelfControlIntoAllowtime()
                        } label: {
                            Label("SelfControl", systemImage: "square.and.arrow.down")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(LlamaTheme.accentInk)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)

                HStack(spacing: 8) {
                    TextField("Agregar sitio (x.com, instagram.com)", text: $newAllowtimeDomain)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(LlamaTheme.fill))
                        .onSubmit {
                            let val = newAllowtimeDomain
                            newAllowtimeDomain = ""
                            store.addAllowtimeDomains(val)
                        }
                    Button("Agregar") {
                        let val = newAllowtimeDomain
                        newAllowtimeDomain = ""
                        store.addAllowtimeDomains(val)
                    }
                    .buttonStyle(SecondaryZenButtonStyle())
                    .disabled(newAllowtimeDomain.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.horizontal, 14)

                domainList(domains: cfg.domains, removable: !(cfg.enabled && isStrictLocked)) { domain in
                    store.removeAllowtimeDomain(domain)
                }

                Rectangle().fill(LlamaTheme.line.opacity(0.5)).frame(height: 0.5).padding(.leading, 14)

                HStack(spacing: 8) {
                    Image(systemName: cfg.strictDailyLock ? "lock.fill" : "lock.open")
                        .font(.system(size: 12.5))
                        .foregroundColor(cfg.strictDailyLock ? LlamaTheme.accentInk : LlamaTheme.muted)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Candado diario")
                            .font(.system(size: 12.5, weight: .semibold))
                        Text("Impide quitar sitios o subir el límite hasta mañana.")
                            .font(.system(size: 10.5))
                            .foregroundColor(LlamaTheme.muted)
                    }
                    Spacer()
                    if cfg.strictDailyLock && isStrictLocked {
                        Label("Hasta mañana", systemImage: "lock.fill")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .foregroundColor(LlamaTheme.accentInk)
                            .background(Capsule().fill(LlamaTheme.accentSoft))
                    } else {
                        Toggle("Candado diario", isOn: Binding(
                            get: { cfg.strictDailyLock },
                            set: { store.setAllowtimeStrictDailyLock($0) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            }
            .llamaSurface()
        }
    }

    // MARK: - Shared Domain List Component

    private func domainList(domains: [String], removable: Bool, onRemove: @escaping (String) -> Void) -> some View {
        Group {
            if domains.isEmpty {
                Text("Sin sitios en esta lista.")
                    .font(.system(size: 12.5))
                    .foregroundColor(LlamaTheme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(domains.enumerated()), id: \.element) { idx, domain in
                            HStack(spacing: 8) {
                                Image(systemName: removable ? "globe" : "lock.fill")
                                    .font(.system(size: 11.5))
                                    .foregroundColor(removable ? LlamaTheme.muted : LlamaTheme.accentInk)
                                    .frame(width: 16)
                                Text(domain)
                                    .font(.system(size: 12.5, design: .monospaced))
                                    .foregroundColor(LlamaTheme.ink)
                                    .lineLimit(1)
                                Spacer()
                                if removable {
                                    Button {
                                        onRemove(domain)
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(LlamaTheme.badInk)
                                            .frame(width: 22, height: 22)
                                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(LlamaTheme.badSoft))
                                    }
                                    .buttonStyle(.plain)
                                    .opacity(hoveredDomain == domain ? 1 : 0.28)
                                    .help("Quitar \(domain)")
                                    .accessibilityLabel("Quitar \(domain)")
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6.5)
                            .onHover { isOver in
                                hoveredDomain = isOver ? domain : (hoveredDomain == domain ? nil : hoveredDomain)
                            }
                            if idx < domains.count - 1 {
                                Rectangle()
                                    .fill(LlamaTheme.line.opacity(0.45))
                                    .frame(height: 0.5)
                                    .padding(.leading, 38)
                            }
                        }
                    }
                }
                .frame(maxHeight: 132)
            }
        }
    }

    // MARK: - Toast, About & Keyboard Shortcuts

    private func toastPill(_ toast: ZenToast) -> some View {
        HStack(spacing: 8) {
            Text(toast.message)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(toast.isError ? LlamaTheme.badInk : LlamaTheme.ink)
            if toast.canUndo {
                Button("Deshacer") { store.performUndo() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(LlamaTheme.accentInk)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(LlamaTheme.surface)
                .shadow(color: .black.opacity(0.16), radius: 8, y: 3)
        )
        .overlay(Capsule().strokeBorder(toast.isError ? LlamaTheme.bad.opacity(0.5) : LlamaTheme.line.opacity(0.5), lineWidth: 0.5))
    }

    private var aboutPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Acerca de Huerequeque Zen")
                .font(.system(size: 17, weight: .bold, design: .rounded))
            VStack(alignment: .leading, spacing: 8) {
                Text("Bloqueo irrompible en la barra de menú: combina /etc/hosts, firewall PF y un guardián root en launchd que sobrevive reinicios.")
                    .fixedSize(horizontal: false, vertical: true)
                Text("Modo Bloqueo: sesiones on-demand que nunca se pueden cancelar ni acortar, solo extender o sumar sitios.")
                    .fixedSize(horizontal: false, vertical: true)
                Text("Modo Allowtime: bloquea sitios extra distractorios 24/7 y abre ventanas cronometradas con presupuesto diario; al vencer, cierra el paso solo.")
                    .fixedSize(horizontal: false, vertical: true)
                Rectangle().fill(LlamaTheme.line.opacity(0.5)).frame(height: 0.5)
                Text("100% local, sin cuentas, nube ni telemetría.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 12.5))
            .padding(13)
            .llamaSurface()

            Text("Santiago de Tuna Computer · " + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"))
                .font(.system(size: 11))
                .foregroundColor(LlamaTheme.muted)
        }
        .padding(16)
        .frame(width: 312)
        .background(LlamaTheme.bg)
        .foregroundColor(LlamaTheme.ink)
    }

    private var keyboardShortcuts: some View {
        Group {
            Button("") { store.selectedTab = .block }
                .keyboardShortcut("1", modifiers: .command)
            Button("") { store.selectedTab = .allowtime }
                .keyboardShortcut("2", modifiers: .command)
            Button("") { store.performUndo() }
                .keyboardShortcut("z", modifiers: .command)
            Button("") {
                if store.selectedTab == .block && !store.daemonState.isBlockActive(at: store.now) {
                    store.startOnDemandBlock()
                } else if store.selectedTab == .allowtime {
                    if store.daemonState.isAllowtimeWindowOpen(at: store.now) {
                        store.closeAllowtimeWindow()
                    } else {
                        store.openAllowtimeWindow()
                    }
                }
            }
            .keyboardShortcut(.return, modifiers: .command)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }
}

private struct PrimaryZenButtonStyle: ButtonStyle {
    let tint: Color
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(isEnabled ? LlamaTheme.accentOn : LlamaTheme.muted)
            .background(
                RoundedRectangle(cornerRadius: LlamaTheme.radioLista, style: .continuous)
                    .fill(isEnabled ? tint : LlamaTheme.fill)
            )
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}

private struct SecondaryZenButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 11)
            .padding(.vertical, 6.5)
            .foregroundColor(isEnabled ? LlamaTheme.accentInk : LlamaTheme.muted)
            .background(
                RoundedRectangle(cornerRadius: LlamaTheme.radioControl, style: .continuous)
                    .fill(isEnabled ? LlamaTheme.accentSoft : LlamaTheme.fill)
            )
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}
