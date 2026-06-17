import AppKit

final class AppLaunchDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        openSettingsWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettingsWindow()
        return false
    }

    private func openSettingsWindow() {
        guard !isRunningTests else { return }

        DispatchQueue.main.async {
            SettingsWindowController.shared.show()
        }
    }

    private var isRunningTests: Bool {
        NSClassFromString("XCTestCase") != nil
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.arguments.contains { argument in
                argument == "-XCTest"
                    || argument.contains("XCTest")
                    || argument.hasSuffix(".xctest")
            }
            || Bundle.allBundles.contains { bundle in
                bundle.bundlePath.hasSuffix(".xctest")
            }
    }
}
