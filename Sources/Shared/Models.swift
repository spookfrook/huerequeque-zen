import Foundation

enum ZenConstants {
    static let bundleIdentifier = "com.santiagodetuna.huerequeque-zen"
    static let daemonLabel = "com.santiagodetuna.huerequeque-zen.daemon"
    static let anchorName = "com.santiagodetuna.huerequeque-zen"
    static let daemonVersion = "1.0.0"

    static let socketPath = "/var/run/huerequeque-zen.sock"
    static let supportDir = "/Library/Application Support/HuerequequeZen"
    static let stateFilePath = "/Library/Application Support/HuerequequeZen/state.json"
    static let ownerUIDPath = "/Library/Application Support/HuerequequeZen/owner.uid"
    static let daemonBinaryPath = "/Library/PrivilegedHelperTools/com.santiagodetuna.huerequeque-zen.daemon"
    static let launchDaemonPlistPath = "/Library/LaunchDaemons/com.santiagodetuna.huerequeque-zen.daemon.plist"
    static let pfAnchorPath = "/etc/pf.anchors/com.santiagodetuna.huerequeque-zen"
    static let pfConfPath = "/etc/pf.conf"
    static let hostsPath = "/etc/hosts"
    static let logDir = "/Library/Logs/HuerequequeZen"
    static let logFilePath = "/Library/Logs/HuerequequeZen/daemon.log"

    static let minBlockSeconds = 60
    static let maxBlockSeconds = 24 * 3600
    static let maxExtendSeconds = 24 * 3600
    static let minAllowtimeWindowSeconds = 60
    static let maxAllowtimeWindowSeconds = 4 * 3600
}

enum BlockMode: String, Codable, CaseIterable, Equatable {
    case blocklist
    case allowlist

    var title: String {
        switch self {
        case .blocklist: return "Bloquear lista"
        case .allowlist: return "Solo permitir"
        }
    }

    var shortLabel: String {
        switch self {
        case .blocklist: return "Lista negra"
        case .allowlist: return "Solo permitir"
        }
    }
}

enum DomainNormalizer {
    private static let mobileSubdomainTargets: Set<String> = [
        "x.com", "twitter.com", "instagram.com", "facebook.com",
        "reddit.com", "youtube.com", "tiktok.com", "threads.net"
    ]

    /// Splits comma/newline/space-separated input into clean, deduplicated normalized domains.
    static func parseInput(_ raw: String) -> [String] {
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;"))
        let tokens = raw.components(separatedBy: separators)
        return normalizeList(tokens)
    }

    static func normalizeList(_ rawList: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for item in rawList {
            guard let clean = normalize(item), !seen.contains(clean) else { continue }
            seen.insert(clean)
            result.append(clean)
        }
        return result
    }

    static func normalize(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s.isEmpty { return nil }

        // Strip scheme if user pasted a full URL
        if let schemeRange = s.range(of: "://") {
            s = String(s[schemeRange.upperBound...])
        }
        // Strip leading wildcard
        if s.hasPrefix("*.") {
            s = String(s.dropFirst(2))
        }
        // Strip path, query, fragment
        if let cut = s.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) {
            s = String(s[..<cut])
        }
        // Strip credentials user@host
        if let at = s.lastIndex(of: "@") {
            s = String(s[s.index(after: at)...])
        }
        // Strip port :8080
        if let colon = s.firstIndex(of: ":") {
            s = String(s[..<colon])
        }
        // Trim surrounding dots
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "."))

        // Reject loopback or invalid hostnames
        guard !s.isEmpty,
              s != "localhost",
              !s.hasSuffix(".local"),
              !s.hasSuffix(".localhost"),
              s.count <= 253,
              s.contains(".")
        else { return nil }

        let labels = s.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else { return nil }
        for label in labels {
            guard !label.isEmpty, label.count <= 63 else { return nil }
            guard !label.hasPrefix("-"), !label.hasSuffix("-") else { return nil }
            for ch in label {
                let valid = (ch >= "a" && ch <= "z") || (ch >= "0" && ch <= "9") || ch == "-"
                if !valid { return nil }
            }
        }
        // Reject raw IPv4 addresses (e.g. 127.0.0.1) so users don't accidentally lock loopback
        if labels.allSatisfy({ $0.allSatisfy({ $0 >= "0" && $0 <= "9" }) }) {
            return nil
        }
        // TLD must contain at least one letter
        if let tld = labels.last, !tld.contains(where: { $0 >= "a" && $0 <= "z" }) {
            return nil
        }
        return s
    }

    /// Expands a normalized domain into the exact hosts to place in /etc/hosts and resolve for PF.
    static func expandedHosts(for domains: [String]) -> [String] {
        var seen = Set<String>()
        var hosts: [String] = []
        func add(_ host: String) {
            if !seen.contains(host) {
                seen.insert(host)
                hosts.append(host)
            }
        }

        for raw in domains {
            guard let domain = normalize(raw) else { continue }
            let apex = domain.hasPrefix("www.") ? String(domain.dropFirst(4)) : domain
            add(domain)
            if domain.hasPrefix("www.") {
                add(apex)
            } else {
                let labels = domain.split(separator: ".")
                if labels.count == 2 {
                    add("www.\(domain)")
                }
            }
            if mobileSubdomainTargets.contains(apex) {
                add("m.\(apex)")
                add("mobile.\(apex)")
            }
        }
        return hosts
    }
}

struct ActiveBlock: Codable, Equatable {
    let id: String
    let mode: BlockMode
    var domains: [String]
    let startedAt: Date
    var endsAt: Date
    var label: String?
}

struct AllowtimeConfig: Codable, Equatable {
    var enabled: Bool
    var domains: [String]
    /// 0 means unlimited daily budget (still requires opening a timed window each time).
    var dailyBudgetSeconds: Int
    var defaultWindowSeconds: Int
    /// When enabled, once Allowtime is active today you cannot disable it, remove domains, or raise budget until tomorrow.
    var strictDailyLock: Bool

    static let `default` = AllowtimeConfig(
        enabled: false,
        domains: ["x.com", "twitter.com", "instagram.com"],
        dailyBudgetSeconds: 30 * 60,
        defaultWindowSeconds: 10 * 60,
        strictDailyLock: false
    )
}

struct AllowtimeRuntime: Codable, Equatable {
    var dayKey: String
    var usedTodaySeconds: Int
    var windowStartedAt: Date?
    var windowEndsAt: Date?
    var lockedDayKey: String?

    static func empty(dayKey: String) -> AllowtimeRuntime {
        AllowtimeRuntime(
            dayKey: dayKey,
            usedTodaySeconds: 0,
            windowStartedAt: nil,
            windowEndsAt: nil,
            lockedDayKey: nil
        )
    }
}

enum EffectiveBlockingSpec: Equatable {
    case none
    case blocklist(domains: [String])
    case allowlist(allowedDomains: [String], extraBlockedDomains: [String])

    var isBlockingAnything: Bool {
        switch self {
        case .none: return false
        case .blocklist(let domains): return !domains.isEmpty
        case .allowlist: return true
        }
    }
}

enum AllowtimeOpenCheck: Equatable {
    case allowed(maxGrantSeconds: Int)
    case unavailable(reason: String)
}

struct DaemonState: Codable, Equatable {
    var schemaVersion: Int
    var daemonVersion: String
    var activeBlock: ActiveBlock?
    var allowtimeConfig: AllowtimeConfig
    var allowtimeRuntime: AllowtimeRuntime
    var lastEnforcedAt: Date?
    var lastError: String?

    static func initial(now: Date = Date(), calendar: Calendar = .current) -> DaemonState {
        DaemonState(
            schemaVersion: 1,
            daemonVersion: ZenConstants.daemonVersion,
            activeBlock: nil,
            allowtimeConfig: .default,
            allowtimeRuntime: .empty(dayKey: Self.dayKey(for: now, calendar: calendar)),
            lastEnforcedAt: nil,
            lastError: nil
        )
    }

    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", comps.year ?? 2026, comps.month ?? 1, comps.day ?? 1)
    }

    func isBlockActive(at now: Date) -> Bool {
        guard let block = activeBlock else { return false }
        return block.endsAt > now
    }

    func blockRemainingSeconds(at now: Date) -> Int {
        guard let block = activeBlock else { return 0 }
        return max(0, Int(ceil(block.endsAt.timeIntervalSince(now))))
    }

    func isAllowtimeWindowOpen(at now: Date) -> Bool {
        guard allowtimeConfig.enabled,
              let end = allowtimeRuntime.windowEndsAt,
              let start = allowtimeRuntime.windowStartedAt,
              end > now,
              now >= start.addingTimeInterval(-5)
        else { return false }
        return true
    }

    func allowtimeWindowRemainingSeconds(at now: Date) -> Int {
        guard isAllowtimeWindowOpen(at: now), let end = allowtimeRuntime.windowEndsAt else { return 0 }
        return max(0, Int(ceil(end.timeIntervalSince(now))))
    }

    func effectiveAllowtimeUsedToday(at now: Date, calendar: Calendar = .current) -> Int {
        let today = Self.dayKey(for: now, calendar: calendar)
        let base = (allowtimeRuntime.dayKey == today) ? allowtimeRuntime.usedTodaySeconds : 0
        if isAllowtimeWindowOpen(at: now), let start = allowtimeRuntime.windowStartedAt {
            let liveElapsed = max(0, Int(now.timeIntervalSince(start)))
            return base + liveElapsed
        }
        return base
    }

    /// Returns remaining daily budget in seconds, or nil if dailyBudgetSeconds == 0 (unlimited).
    func allowtimeBudgetRemaining(at now: Date, calendar: Calendar = .current) -> Int? {
        guard allowtimeConfig.dailyBudgetSeconds > 0 else { return nil }
        let used = effectiveAllowtimeUsedToday(at: now, calendar: calendar)
        return max(0, allowtimeConfig.dailyBudgetSeconds - used)
    }

    func isStrictDailyLockActive(at now: Date, calendar: Calendar = .current) -> Bool {
        guard allowtimeConfig.enabled, allowtimeConfig.strictDailyLock else { return false }
        let today = Self.dayKey(for: now, calendar: calendar)
        return allowtimeRuntime.lockedDayKey == today
    }

    func isAllowtimeGuarding(at now: Date) -> Bool {
        allowtimeConfig.enabled && !allowtimeConfig.domains.isEmpty && !isAllowtimeWindowOpen(at: now)
    }

    func allowtimeDomainsBlockedByOnDemand(at now: Date) -> Bool {
        guard let block = activeBlock, block.endsAt > now, !allowtimeConfig.domains.isEmpty else { return false }
        switch block.mode {
        case .blocklist:
            let onDemandSet = Set(block.domains)
            return allowtimeConfig.domains.allSatisfy { onDemandSet.contains($0) }
        case .allowlist:
            let allowedSet = Set(block.domains)
            return allowtimeConfig.domains.allSatisfy { !allowedSet.contains($0) }
        }
    }

    func canOpenAllowtimeWindow(at now: Date, calendar: Calendar = .current) -> AllowtimeOpenCheck {
        guard allowtimeConfig.enabled else {
            return .unavailable(reason: "Activa primero la guardia Allowtime.")
        }
        guard !allowtimeConfig.domains.isEmpty else {
            return .unavailable(reason: "Agrega al menos un sitio a Allowtime.")
        }
        if isAllowtimeWindowOpen(at: now) {
            return .unavailable(reason: "Ya tienes una ventana abierta.")
        }
        if allowtimeDomainsBlockedByOnDemand(at: now) {
            return .unavailable(reason: "Hay un bloqueo irrompible activo sobre estos sitios.")
        }
        if let remaining = allowtimeBudgetRemaining(at: now, calendar: calendar) {
            if remaining < ZenConstants.minAllowtimeWindowSeconds {
                return .unavailable(reason: "Presupuesto de hoy agotado. Se renueva mañana.")
            }
            return .allowed(maxGrantSeconds: min(remaining, ZenConstants.maxAllowtimeWindowSeconds))
        }
        return .allowed(maxGrantSeconds: ZenConstants.maxAllowtimeWindowSeconds)
    }

    func effectiveBlockingSpec(at now: Date) -> EffectiveBlockingSpec {
        let guardedAllowtime = isAllowtimeGuarding(at: now) ? allowtimeConfig.domains : []

        if let block = activeBlock, block.endsAt > now {
            switch block.mode {
            case .blocklist:
                let combined = DomainNormalizer.normalizeList(block.domains + guardedAllowtime)
                return combined.isEmpty ? .none : .blocklist(domains: combined)
            case .allowlist:
                // In allowlist mode, exclude any guarded Allowtime domains from the allowed set!
                let guardedSet = Set(guardedAllowtime)
                let filteredAllowed = block.domains.filter { !guardedSet.contains($0) }
                return .allowlist(allowedDomains: filteredAllowed, extraBlockedDomains: guardedAllowtime)
            }
        }

        return guardedAllowtime.isEmpty ? .none : .blocklist(domains: guardedAllowtime)
    }
}

// MARK: - IPC Protocol

enum DaemonCommand: String, Codable {
    case ping
    case startBlock = "start_block"
    case extendBlock = "extend_block"
    case addBlockDomains = "add_block_domains"
    case updateAllowtimeConfig = "update_allowtime_config"
    case openAllowtimeWindow = "open_allowtime_window"
    case closeAllowtimeWindow = "close_allowtime_window"
}

struct DaemonRequest: Codable {
    let command: DaemonCommand
    var domains: [String]?
    var mode: BlockMode?
    var durationSeconds: Int?
    var label: String?
    var allowtimeConfig: AllowtimeConfig?
}

struct DaemonResponse: Codable {
    let ok: Bool
    let message: String?
    let state: DaemonState?
}

// MARK: - App Profiles & SelfControl Import

struct BlockProfile: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var mode: BlockMode
    var domains: [String]
    var defaultMinutes: Int

    static let defaults: [BlockProfile] = [
        BlockProfile(
            id: "enfoque",
            name: "Enfoque",
            mode: .blocklist,
            domains: ["x.com", "twitter.com", "instagram.com", "reddit.com", "youtube.com"],
            defaultMinutes: 60
        ),
        BlockProfile(
            id: "profundo",
            name: "Profundo",
            mode: .blocklist,
            domains: [
                "x.com", "twitter.com", "instagram.com", "facebook.com",
                "reddit.com", "youtube.com", "tiktok.com", "threads.net",
                "news.ycombinator.com"
            ],
            defaultMinutes: 120
        ),
        BlockProfile(
            id: "solo-trabajo",
            name: "Solo docs",
            mode: .allowlist,
            domains: ["github.com", "linear.app", "docs.google.com"],
            defaultMinutes: 45
        )
    ]
}

enum SelfControlImporter {
    static func readBlocklist() -> [String] {
        guard let defaults = UserDefaults(suiteName: "org.eyebeam.SelfControl"),
              let raw = defaults.stringArray(forKey: "Blocklist")
        else { return [] }
        return DomainNormalizer.normalizeList(raw)
    }
}

// MARK: - Time Formatting Helpers

enum ZenFormat {
    static func countdown(_ totalSeconds: Int) -> String {
        let clamped = max(0, totalSeconds)
        let h = clamped / 3600
        let m = (clamped % 3600) / 60
        let s = clamped % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }

    static func compactMenuCountdown(_ totalSeconds: Int) -> String {
        let clamped = max(0, totalSeconds)
        let h = clamped / 3600
        let m = (clamped % 3600) / 60
        let s = clamped % 60
        if h > 0 {
            return String(format: "%dh%02d", h, m)
        }
        return String(format: "%d:%02d", m, s)
    }

    static func durationLabel(minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60
        let rem = minutes % 60
        if rem == 0 { return "\(h) h" }
        return "\(h) h \(rem) min"
    }

    static func endClockString(from date: Date, calendar: Calendar = .current) -> String {
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", comps.hour ?? 0, comps.minute ?? 0)
    }
}
