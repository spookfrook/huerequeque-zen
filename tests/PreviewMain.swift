import AppKit
import SwiftUI

@MainActor
func renderSnapshot(name: String, store: ZenStore, dark: Bool, outputDir: URL) throws {
    let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
    let host = NSHostingView(rootView: Panel(store: store))
    host.appearance = appearance
    let size = host.fittingSize
    host.frame = NSRect(origin: .zero, size: size)

    // Off-screen non-interactive window (per aprendizaje #52: never steal focus or mouse events)
    let window = NSWindow(
        contentRect: NSRect(x: -10000, y: -10000, width: size.width, height: size.height),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    window.ignoresMouseEvents = true
    window.appearance = appearance
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.15))

    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
        fatalError("No render for \(name)")
    }
    host.cacheDisplay(in: host.bounds, to: rep)
    let file = outputDir.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png")
    try rep.representation(using: .png, properties: [:])!.write(to: file)
    print("Rendered \(file.lastPathComponent) (\(Int(size.width))x\(Int(size.height)))")
}

@main
struct PreviewRunner {
@MainActor
static func main() throws {
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let defaults = UserDefaults(suiteName: "com.santiagodetuna.huerequeque-zen.preview")!
defaults.removePersistentDomain(forName: "com.santiagodetuna.huerequeque-zen.preview")

let now = Date()

// 1. Block Idle (Daemon ready)
let idleState = DaemonState.initial(now: now)
let storeIdle = ZenStore(defaults: defaults, previewState: idleState, previewConnected: true, previewTab: .block)

// 2. Block Active (Irrompible)
var lockedState = DaemonState.initial(now: now)
lockedState.activeBlock = ActiveBlock(
    id: "preview-1",
    mode: .blocklist,
    domains: ["x.com", "twitter.com", "instagram.com", "reddit.com", "youtube.com"],
    startedAt: now.addingTimeInterval(-1080),
    endsAt: now.addingTimeInterval(2520),
    label: "Enfoque"
)
let storeLocked = ZenStore(defaults: defaults, previewState: lockedState, previewConnected: true, previewTab: .block)

// 3. Allowtime Guarding (Cerrado, 10/30 min usados hoy)
var allowGuarded = DaemonState.initial(now: now)
allowGuarded.allowtimeConfig = AllowtimeConfig(
    enabled: true,
    domains: ["x.com", "twitter.com", "instagram.com"],
    dailyBudgetSeconds: 30 * 60,
    defaultWindowSeconds: 10 * 60,
    strictDailyLock: true
)
allowGuarded.allowtimeRuntime.usedTodaySeconds = 10 * 60
allowGuarded.allowtimeRuntime.lockedDayKey = DaemonState.dayKey(for: now)
let storeAllowGuarded = ZenStore(defaults: defaults, previewState: allowGuarded, previewConnected: true, previewTab: .allowtime)

// 4. Allowtime Open Window (07:42 restantes)
var allowOpen = allowGuarded
allowOpen.allowtimeRuntime.windowStartedAt = now.addingTimeInterval(-138)
allowOpen.allowtimeRuntime.windowEndsAt = now.addingTimeInterval(462)
let storeAllowOpen = ZenStore(defaults: defaults, previewState: allowOpen, previewConnected: true, previewTab: .allowtime)

for dark in [false, true] {
    try renderSnapshot(name: "block-idle", store: storeIdle, dark: dark, outputDir: outDir)
    try renderSnapshot(name: "block-locked", store: storeLocked, dark: dark, outputDir: outDir)
    try renderSnapshot(name: "allowtime-guarded", store: storeAllowGuarded, dark: dark, outputDir: outDir)
    try renderSnapshot(name: "allowtime-open", store: storeAllowOpen, dark: dark, outputDir: outDir)
}

defaults.removePersistentDomain(forName: "com.santiagodetuna.huerequeque-zen.preview")
}
}
