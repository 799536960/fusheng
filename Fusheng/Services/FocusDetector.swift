import AppKit
import ApplicationServices
import Foundation

protocol AccessibilityInspecting {
    func isProcessTrusted(prompt: Bool) -> Bool
    func focusedElement() -> AnyObject?
    func role(of element: AnyObject) -> String?
    func hasSelectedTextRange(_ element: AnyObject) -> Bool
}

struct SystemAccessibilityInspector: AccessibilityInspecting {
    func isProcessTrusted(prompt: Bool) -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func focusedElement() -> AnyObject? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedValue: AnyObject?
        let status = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        )

        guard status == .success else { return nil }
        return focusedValue
    }

    func role(of element: AnyObject) -> String? {
        guard CFGetTypeID(element) == AXUIElementGetTypeID() else { return nil }

        var roleValue: AnyObject?
        let status = AXUIElementCopyAttributeValue(
            element as! AXUIElement,
            kAXRoleAttribute as CFString,
            &roleValue
        )

        guard status == .success else { return nil }
        return roleValue as? String
    }

    func hasSelectedTextRange(_ element: AnyObject) -> Bool {
        guard CFGetTypeID(element) == AXUIElementGetTypeID() else { return false }

        var selectedTextRange: AnyObject?
        let status = AXUIElementCopyAttributeValue(
            element as! AXUIElement,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedTextRange
        )

        return status == .success
    }
}

struct FocusDetector: FocusDetecting, SourceAppProviding {
    private let accessibilityInspector: AccessibilityInspecting
    private let appNameProvider: () -> String

    init(
        accessibilityInspector: AccessibilityInspecting = SystemAccessibilityInspector(),
        appNameProvider: @escaping () -> String = {
            NSWorkspace.shared.frontmostApplication?.localizedName ?? "未知 App"
        }
    ) {
        self.accessibilityInspector = accessibilityInspector
        self.appNameProvider = appNameProvider
    }

    func focusedInputContext() -> FocusInputContext {
        let appName = currentAppName()

        guard accessibilityInspector.isProcessTrusted(prompt: false) else {
            return .accessibilityPermissionMissing(appName: appName)
        }

        guard let focusedElement = accessibilityInspector.focusedElement() else {
            return .noInput(appName: appName)
        }

        if let role = accessibilityInspector.role(of: focusedElement), textRoles.contains(role) {
            return .inputAvailable(appName: appName)
        }

        if accessibilityInspector.hasSelectedTextRange(focusedElement) {
            return .inputAvailable(appName: appName)
        }

        return .noInput(appName: appName)
    }

    func currentAppName() -> String {
        appNameProvider()
    }

    private var textRoles: Set<String> {
        [
            kAXTextFieldRole as String,
            kAXTextAreaRole as String,
            kAXComboBoxRole as String
        ]
    }
}
