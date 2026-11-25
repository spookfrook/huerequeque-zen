import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    var status: NSStatusItem!
    let popover = NSPopover()
    var store: ZenStore!

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = ZenStore()
        self.store = store
        NSApp.appearance = store.appearance.nsAppearance

        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.target = self
        status.button?.action = #selector(togglePanel)
        status.button?.imagePosition = .imageLeading
        status.button?.setAccessibilityLabel("Huerequeque Zen")

        popover.behavior = .transient
        let host = NSHostingController(rootView: Panel(store: store))
        popover.contentViewController = host
        popover.contentSize = host.view.fittingSize

        store.statusChanged = { [weak self] in
            self?.updateStatus()
        }
        updateStatus()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.showPanel()
        }
    }

    @MainActor
    func updateStatus() {
        guard let store = store else { return }
        let image = StatusMark.image(pose: store.menuBarPose)
        status.button?.image = image
        status.button?.title = store.menuBarTitle
        let desc = image.accessibilityDescription ?? "Huerequeque Zen"
        status.button?.setAccessibilityLabel(desc)
        status.button?.toolTip = desc
    }

    @MainActor
    @objc func togglePanel() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            store?.refreshDaemon(silent: true)
            showPanel()
        }
    }

    @MainActor
    func showPanel() {
        guard let button = status.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
