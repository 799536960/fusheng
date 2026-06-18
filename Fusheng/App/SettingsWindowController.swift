import AppKit
import SwiftUI

final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var windowController: NSWindowController?

    private init() {}

    func show() {
        let window = settingsWindow()
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }

        NSApp.setActivationPolicy(.regular)
        raise(window)

        DispatchQueue.main.async {
            self.raise(window)
            window.makeFirstResponder(nil)
        }
    }

    private func settingsWindow() -> NSWindow {
        if let window = windowController?.window {
            return window
        }

        let hostingController = NSHostingController(rootView: SettingsView())
        let window = NSWindow(contentViewController: hostingController)
        window.title = "设置"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.contentMinSize = NSSize(width: 860, height: 680)
        window.setContentSize(NSSize(width: 920, height: 720))
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        window.center()

        let controller = NSWindowController(window: window)
        windowController = controller
        return window
    }

    private func raise(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.makeMain()
        window.orderFrontRegardless()
    }
}
