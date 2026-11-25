import AppKit
import Combine
import Foundation

enum ZenTab: String, CaseIterable {
    case block
    case allowtime

    var title: String {
        switch self {
        case .block: return "Bloqueo"
        case .allowtime: return "Allowtime"
        }
    }
}

enum AppearancePreference: String, CaseIterable, Codable {
    case system
    case light
    case dark

    var title: String {
        switch self {
        case .system: return "Según el sistema"
        case .light: return "Claro"
        case .dark: return "Oscuro"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

struct ZenToast: Equatable {
    let id = UUID()
    let message: String
    let isError: Bool
    let canUndo: Bool
}

@MainActor
final class ZenStore: ObservableObject {
    @Published var selectedTab: ZenTab = .block
    @Published var daemonState: DaemonState
    @Published var daemonConnected: Bool = false
    @Published var isInstallingDaemon: Bool = false

    // On-Demand draft state (stored locally in UserDefaults)
    @Published var profiles: [BlockProfile]
    @Published var selectedProfileID: String
    @Published var durationMinutes: Int = 60
    @Published var useUntilTime: Bool = false
    @Published var untilDate: Date = Date().addingTimeInterval(3600)

    // Allowtime quick window selection
    @Published var selectedWindowMinutes: Int = 10

    // SelfControl integration
    @Published var selfControlDomains: [String] = []

    // Feedback & undo
    @Published var toast: ZenToast?
    @Published var now: Date = Date()
    @Published var appearance: AppearancePreference = .system

    var statusChanged: (() -> Void)?

    private let defaults: UserDefaults
    private let client: SocketClient
    private let isPreview: Bool
    private var timer: Timer?
    private var pollCounter: Int = 0
    private var undoHandler: (() -> Void)?
    private var toastTask: Task<Void, Never>?

    private enum Keys {
        static let profiles = "profiles.v1"
        static let selectedProfile = "selectedProfile.v1"
        static let durationMinutes = "durationMinutes.v1"
        static let allowtimeDraft = "allowtimeDraft.v1"
        static let windowMinutes = "windowMinutes.v1"
        static let appearance = "appearance.v1"
    }

    init(
        defaults: UserDefaults = UserDefaults(suiteName: ZenConstants.bundleIdentifier) ?? .standard,
        socketPath: String = ZenConstants.socketPath,
        previewState: DaemonState? = nil,
        previewConnected: Bool = false,
        previewTab: ZenTab = .block
    ) {
        self.defaults = defaults
        self.client = SocketClient(socketPath: socketPath)
        self.isPreview = (previewState != nil)

        let loadedProfiles: [BlockProfile]
        if let data = defaults.data(forKey: Keys.profiles),
           let decoded = try? JSONDecoder().decode([BlockProfile].self, from: data),
           !decoded.isEmpty {
            loadedProfiles = decoded
        } else {
            loadedProfiles = BlockProfile.defaults
        }
        self.profiles = loadedProfiles

        let savedProfile = defaults.string(forKey: Keys.selectedProfile)
        if let id = savedProfile, loadedProfiles.contains(where: { $0.id == id }) {
            self.selectedProfileID = id
        } else {
            self.selectedProfileID = loadedProfiles.first?.id ?? "enfoque"
        }

        let savedMinutes = defaults.integer(forKey: Keys.durationMinutes)
        if savedMinutes >= 5 && savedMinutes <= 24 * 60 {
            self.durationMinutes = savedMinutes
        }

        let savedWin = defaults.integer(forKey: Keys.windowMinutes)
        if savedWin >= 1 && savedWin <= 120 {
            self.selectedWindowMinutes = savedWin
        }

        if let rawApp = defaults.string(forKey: Keys.appearance),
           let pref = AppearancePreference(rawValue: rawApp) {
            self.appearance = pref
        }

        if let preview = previewState {
            self.daemonState = preview
            self.daemonConnected = previewConnected
            self.selectedTab = previewTab
            self.selfControlDomains = ["x.com", "twitter.com", "instagram.com"]
        } else {
            // Load cached state or daemon state file immediately so first paint is accurate
            if let fileData = try? Data(contentsOf: URL(fileURLWithPath: ZenConstants.stateFilePath)),
               let fileState = try? SocketJSON.decoder().decode(DaemonState.self, from: fileData) {
                self.daemonState = fileState
            } else if let draftData = defaults.data(forKey: Keys.allowtimeDraft),
                      let draftAllowtime = try? JSONDecoder().decode(AllowtimeConfig.self, from: draftData) {
                var initState = DaemonState.initial()
                initState.allowtimeConfig = draftAllowtime
                self.daemonState = initState
            } else {
                self.daemonState = DaemonState.initial()
            }
            self.selfControlDomains = SelfControlImporter.readBlocklist()
            refreshDaemon()
            startTimer()
        }
    }

    var activeProfile: BlockProfile {
        profiles.first(where: { $0.id == selectedProfileID }) ?? profiles[0]
    }

    var activeProfileIndex: Int {
        profiles.firstIndex(where: { $0.id == selectedProfileID }) ?? 0
    }

    var effectiveDurationSeconds: Int {
        if useUntilTime {
            var target = untilDate
            if target <= now.addingTimeInterval(60) {
                target = target.addingTimeInterval(24 * 3600)
            }
            let diff = Int(target.timeIntervalSince(now))
            return max(ZenConstants.minBlockSeconds, min(diff, ZenConstants.maxBlockSeconds))
        }
        return max(ZenConstants.minBlockSeconds, min(durationMinutes * 60, ZenConstants.maxBlockSeconds))
    }

    var menuBarPose: MenuBarPose {
        if daemonState.isBlockActive(at: now) { return .locked }
        if daemonState.isAllowtimeWindowOpen(at: now) { return .allowtimeOpen }
        if daemonState.isAllowtimeGuarding(at: now) { return .guarding }
        return .idle
    }

    var menuBarTitle: String {
        if daemonState.isBlockActive(at: now) {
            return " " + ZenFormat.compactMenuCountdown(daemonState.blockRemainingSeconds(at: now))
        }
        if daemonState.isAllowtimeWindowOpen(at: now) {
            return " " + ZenFormat.compactMenuCountdown(daemonState.allowtimeWindowRemainingSeconds(at: now))
        }
        return ""
    }

    var unimportedSelfControlDomainsForProfile: [String] {
        let existing = Set(activeProfile.domains)
        return selfControlDomains.filter { !existing.contains($0) }
    }

    var unimportedSelfControlDomainsForAllowtime: [String] {
        let existing = Set(daemonState.allowtimeConfig.domains)
        return selfControlDomains.filter { !existing.contains($0) }
    }

    // MARK: - Timer & Daemon Polling

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.now = Date()
                self.pollCounter += 1
                // Poll every 2 seconds while active/window open, every 6 seconds when idle
                let active = self.daemonState.isBlockActive(at: self.now) || self.daemonState.isAllowtimeWindowOpen(at: self.now)
                let interval = active ? 2 : 6
                if self.pollCounter % interval == 0 {
                    self.refreshDaemon(silent: true)
                }
                self.statusChanged?()
            }
        }
    }

    func refreshDaemon(silent: Bool = false) {
        guard !isPreview else { return }
        let client = self.client
        Task.detached(priority: .userInitiated) {
            let result: Result<DaemonResponse, Error>
            do {
                result = .success(try client.send(DaemonRequest(command: .ping)))
            } catch {
                result = .failure(error)
            }
            await MainActor.run {
                switch result {
                case .success(let resp):
                    self.daemonConnected = true
                    if let newState = resp.state {
                        self.daemonState = newState
                        self.saveAllowtimeDraft(newState.allowtimeConfig)
                    }
                case .failure:
                    self.daemonConnected = false
                    if !silent {
                        self.showToast("Activa el guardián irrompible para aplicar bloqueos.", isError: true)
                    }
                }
                self.statusChanged?()
            }
        }
    }

    // MARK: - On-Demand Block Actions

    func selectProfile(_ id: String) {
        guard let profile = profiles.first(where: { $0.id == id }) else { return }
        selectedProfileID = id
        durationMinutes = profile.defaultMinutes
        useUntilTime = false
        defaults.set(id, forKey: Keys.selectedProfile)
        defaults.set(durationMinutes, forKey: Keys.durationMinutes)
    }

    func setDurationMinutes(_ minutes: Int) {
        durationMinutes = max(5, min(minutes, 24 * 60))
        useUntilTime = false
        defaults.set(durationMinutes, forKey: Keys.durationMinutes)
        profiles[activeProfileIndex].defaultMinutes = durationMinutes
        saveProfiles()
    }

    func setProfileMode(_ mode: BlockMode) {
        profiles[activeProfileIndex].mode = mode
        saveProfiles()
    }

    func addDomainsToProfile(_ rawInput: String) {
        let parsed = DomainNormalizer.parseInput(rawInput)
        guard !parsed.isEmpty else {
            showToast("Escribe un dominio válido (ej. x.com).", isError: true)
            return
        }
        let idx = activeProfileIndex
        let previous = profiles[idx].domains
        let merged = DomainNormalizer.normalizeList(previous + parsed)
        let addedCount = merged.count - previous.count
        guard addedCount > 0 else {
            showToast("Ese sitio ya está en la lista.", isError: false)
            return
        }
        profiles[idx].domains = merged
        saveProfiles()
        setUndo { [weak self] in
            guard let self else { return }
            self.profiles[idx].domains = previous
            self.saveProfiles()
        }
        showToast(addedCount == 1 ? "Sitio agregado." : "\(addedCount) sitios agregados.", canUndo: true)
    }

    func removeDomainFromProfile(_ domain: String) {
        let idx = activeProfileIndex
        let previous = profiles[idx].domains
        profiles[idx].domains.removeAll { $0 == domain }
        saveProfiles()
        setUndo { [weak self] in
            guard let self else { return }
            self.profiles[idx].domains = previous
            self.saveProfiles()
        }
        showToast("Quitado \(domain).", canUndo: true)
    }

    func importSelfControlIntoProfile() {
        selfControlDomains = SelfControlImporter.readBlocklist()
        let missing = unimportedSelfControlDomainsForProfile
        guard !missing.isEmpty else {
            showToast("Tu lista ya tiene todo lo de SelfControl.", isError: false)
            return
        }
        addDomainsToProfile(missing.joined(separator: ","))
    }

    func startOnDemandBlock() {
        guard daemonConnected else {
            showToast("Primero activa el guardián irrompible.", isError: true)
            return
        }
        let profile = activeProfile
        guard !profile.domains.isEmpty else {
            showToast("Agrega al menos un dominio antes de bloquear.", isError: true)
            return
        }
        let duration = effectiveDurationSeconds
        let req = DaemonRequest(
            command: .startBlock,
            domains: profile.domains,
            mode: profile.mode,
            durationSeconds: duration,
            label: profile.name
        )
        sendCommand(req, successFallback: "Bloqueo irrompible iniciado.")
    }

    func extendActiveBlock(minutes: Int) {
        let req = DaemonRequest(command: .extendBlock, durationSeconds: minutes * 60)
        sendCommand(req, successFallback: "+\(minutes) min agregados al bloqueo.")
    }

    func addDomainsToActiveBlock(_ rawInput: String) {
        let parsed = DomainNormalizer.parseInput(rawInput)
        guard !parsed.isEmpty else {
            showToast("Escribe un dominio válido (ej. reddit.com).", isError: true)
            return
        }
        // Also persist into current profile if it's blocklist mode so next time it's remembered
        if activeProfile.mode == .blocklist {
            let idx = activeProfileIndex
            profiles[idx].domains = DomainNormalizer.normalizeList(profiles[idx].domains + parsed)
            saveProfiles()
        }
        let req = DaemonRequest(command: .addBlockDomains, domains: parsed)
        sendCommand(req, successFallback: "Sitio sumado al bloqueo activo.")
    }

    // MARK: - Allowtime Actions

    func setAllowtimeEnabled(_ enabled: Bool) {
        var cfg = daemonState.allowtimeConfig
        cfg.enabled = enabled
        updateAllowtimeConfig(cfg, successMessage: enabled ? "Guardia Allowtime activada." : "Guardia Allowtime desactivada.")
    }

    func setAllowtimeDailyBudget(minutes: Int) {
        var cfg = daemonState.allowtimeConfig
        cfg.dailyBudgetSeconds = max(0, minutes * 60)
        updateAllowtimeConfig(cfg, successMessage: minutes == 0 ? "Presupuesto sin límite." : "Presupuesto diario: \(minutes) min.")
    }

    func setAllowtimeStrictDailyLock(_ locked: Bool) {
        var cfg = daemonState.allowtimeConfig
        cfg.strictDailyLock = locked
        updateAllowtimeConfig(cfg, successMessage: locked ? "Candado diario activado hasta mañana." : "Candado diario desactivado.")
    }

    func addAllowtimeDomains(_ rawInput: String) {
        let parsed = DomainNormalizer.parseInput(rawInput)
        guard !parsed.isEmpty else {
            showToast("Escribe un dominio válido (ej. x.com).", isError: true)
            return
        }
        var cfg = daemonState.allowtimeConfig
        let previous = cfg.domains
        cfg.domains = DomainNormalizer.normalizeList(previous + parsed)
        guard cfg.domains.count > previous.count else {
            showToast("Ese sitio ya está en Allowtime.", isError: false)
            return
        }
        updateAllowtimeConfig(cfg, successMessage: "Sitio sumado a Allowtime.")
    }

    func removeAllowtimeDomain(_ domain: String) {
        var cfg = daemonState.allowtimeConfig
        cfg.domains.removeAll { $0 == domain }
        updateAllowtimeConfig(cfg, successMessage: "Quitado \(domain) de Allowtime.")
    }

    func importSelfControlIntoAllowtime() {
        selfControlDomains = SelfControlImporter.readBlocklist()
        let missing = unimportedSelfControlDomainsForAllowtime
        guard !missing.isEmpty else {
            showToast("Allowtime ya tiene tu lista de SelfControl.", isError: false)
            return
        }
        addAllowtimeDomains(missing.joined(separator: ","))
    }

    func setSelectedWindowMinutes(_ minutes: Int) {
        selectedWindowMinutes = max(1, min(minutes, 120))
        defaults.set(selectedWindowMinutes, forKey: Keys.windowMinutes)
    }

    func openAllowtimeWindow() {
        guard daemonConnected else {
            showToast("Primero activa el guardián irrompible.", isError: true)
            return
        }
        let req = DaemonRequest(command: .openAllowtimeWindow, durationSeconds: selectedWindowMinutes * 60)
        sendCommand(req, successFallback: "Ventana abierta por \(selectedWindowMinutes) min.")
    }

    func closeAllowtimeWindow() {
        guard daemonConnected else { return }
        let req = DaemonRequest(command: .closeAllowtimeWindow)
        sendCommand(req, successFallback: "Ventana cerrada. Sitios bloqueados.")
    }

    private func updateAllowtimeConfig(_ config: AllowtimeConfig, successMessage: String) {
        if !daemonConnected {
            // Allow editing draft locally before daemon installation
            daemonState.allowtimeConfig = config
            saveAllowtimeDraft(config)
            showToast(config.enabled ? "Guardado. Activa el guardián para hacerlo irrompible." : "Configuración guardada.")
            statusChanged?()
            return
        }
        let req = DaemonRequest(command: .updateAllowtimeConfig, allowtimeConfig: config)
        sendCommand(req, successFallback: successMessage)
    }

    // MARK: - Daemon Installation (1-time macOS admin authorization)

    func installDaemon() {
        guard !isPreview, !isInstallingDaemon else { return }
        guard let scriptURL = Bundle.main.url(forResource: "install-daemon", withExtension: "sh"),
              let daemonURL = Bundle.main.url(forAuxiliaryExecutable: "huerequeque-zen-daemon") ??
                Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/huerequeque-zen-daemon") as URL?
        else {
            showToast("No se encontró el instalador del guardián dentro de la app.", isError: true)
            return
        }

        let ownerUID = getuid()
        isInstallingDaemon = true
        let escapedScript = scriptURL.path.replacingOccurrences(of: "'", with: "'\\''")
        let escapedDaemon = daemonURL.path.replacingOccurrences(of: "'", with: "'\\''")
        let shellCmd = "/bin/bash '\(escapedScript)' '\(escapedDaemon)' '\(ownerUID)'"
        let appleScriptSource = "do shell script \"\(shellCmd.replacingOccurrences(of: "\"", with: "\\\""))\" with administrator privileges with prompt \"Huerequeque Zen necesita instalar su guardián irrompible (solo esta vez).\""

        Task.detached(priority: .userInitiated) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            proc.arguments = ["-e", appleScriptSource]
            let errPipe = Pipe()
            proc.standardError = errPipe
            do {
                try proc.run()
                proc.waitUntilExit()
                let errText = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let succeeded = (proc.terminationStatus == 0)

                if succeeded {
                    // Wait briefly for launchd to bind the Unix socket
                    try? await Task.sleep(nanoseconds: 700_000_000)
                }

                await MainActor.run {
                    self.isInstallingDaemon = false
                    if succeeded {
                        self.refreshDaemon(silent: true)
                        // Push any locally configured Allowtime draft to the freshly installed daemon
                        let draft = self.daemonState.allowtimeConfig
                        Task {
                            try? await Task.sleep(nanoseconds: 400_000_000)
                            await MainActor.run {
                                if self.daemonConnected {
                                    self.sendCommand(
                                        DaemonRequest(command: .updateAllowtimeConfig, allowtimeConfig: draft),
                                        successFallback: "Guardián irrompible activo."
                                    )
                                } else {
                                    self.showToast("Guardián instalado. Verificando conexión...", isError: false)
                                }
                            }
                        }
                    } else if errText.contains("-128") || errText.lowercased().contains("cancel") {
                        self.showToast("Instalación cancelada.", isError: false)
                    } else {
                        self.showToast("No se pudo instalar el guardián.", isError: true)
                    }
                }
            } catch {
                await MainActor.run {
                    self.isInstallingDaemon = false
                    self.showToast("Error al lanzar la autorización.", isError: true)
                }
            }
        }
    }

    // MARK: - Helpers

    func setAppearance(_ pref: AppearancePreference) {
        appearance = pref
        defaults.set(pref.rawValue, forKey: Keys.appearance)
        NSApp.appearance = pref.nsAppearance
    }

    func performUndo() {
        guard let handler = undoHandler else { return }
        undoHandler = nil
        handler()
        toast = nil
    }

    func quitApp() {
        NSApp.terminate(nil)
    }

    private func sendCommand(_ request: DaemonRequest, successFallback: String) {
        guard !isPreview else { return }
        let client = self.client
        Task.detached(priority: .userInitiated) {
            let result: Result<DaemonResponse, Error>
            do {
                result = .success(try client.send(request))
            } catch {
                result = .failure(error)
            }
            await MainActor.run {
                switch result {
                case .success(let resp):
                    self.daemonConnected = true
                    if let newState = resp.state {
                        self.daemonState = newState
                        self.saveAllowtimeDraft(newState.allowtimeConfig)
                    }
                    if resp.ok {
                        self.showToast(resp.message ?? successFallback, isError: false)
                    } else {
                        self.showToast(resp.message ?? "No se pudo aplicar el cambio.", isError: true)
                    }
                case .failure(let error):
                    self.daemonConnected = false
                    self.showToast(error.localizedDescription, isError: true)
                }
                self.statusChanged?()
            }
        }
    }

    private func saveProfiles() {
        if let data = try? JSONEncoder().encode(profiles) {
            defaults.set(data, forKey: Keys.profiles)
        }
    }

    private func saveAllowtimeDraft(_ config: AllowtimeConfig) {
        if let data = try? JSONEncoder().encode(config) {
            defaults.set(data, forKey: Keys.allowtimeDraft)
        }
    }

    private func setUndo(_ action: @escaping () -> Void) {
        undoHandler = action
    }

    private func showToast(_ message: String, isError: Bool = false, canUndo: Bool = false) {
        if !canUndo { undoHandler = nil }
        toast = ZenToast(message: message, isError: isError, canUndo: canUndo)
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.toast = nil
            }
        }
    }
}
