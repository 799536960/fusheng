import AppKit
import ApplicationServices
import Foundation

protocol AccessibilityInspecting {
    func isProcessTrusted(prompt: Bool) -> Bool
    func focusedElement() -> AnyObject?
    func role(of element: AnyObject) -> String?
    func hasSelectedTextRange(_ element: AnyObject) -> Bool
    func parentElement(of element: AnyObject) -> AnyObject?
    func childElements(of element: AnyObject) -> [AnyObject]
}

extension AccessibilityInspecting {
    func parentElement(of element: AnyObject) -> AnyObject? {
        nil
    }

    func childElements(of element: AnyObject) -> [AnyObject] {
        []
    }
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

    func parentElement(of element: AnyObject) -> AnyObject? {
        guard CFGetTypeID(element) == AXUIElementGetTypeID() else { return nil }

        var parentValue: AnyObject?
        let status = AXUIElementCopyAttributeValue(
            element as! AXUIElement,
            kAXParentAttribute as CFString,
            &parentValue
        )

        guard status == .success else { return nil }
        return parentValue
    }

    func childElements(of element: AnyObject) -> [AnyObject] {
        guard CFGetTypeID(element) == AXUIElementGetTypeID() else { return [] }

        var childrenValue: AnyObject?
        let status = AXUIElementCopyAttributeValue(
            element as! AXUIElement,
            kAXChildrenAttribute as CFString,
            &childrenValue
        )

        guard status == .success else { return [] }
        return childrenValue as? [AnyObject] ?? []
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

        if isTextInputElement(focusedElement) ||
            hasTextInputAncestor(of: focusedElement) ||
            hasTextInputDescendant(of: focusedElement) {
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

    private func isTextInputElement(_ element: AnyObject) -> Bool {
        if let role = accessibilityInspector.role(of: element), textRoles.contains(role) {
            return true
        }

        return accessibilityInspector.hasSelectedTextRange(element)
    }

    private func hasTextInputAncestor(of element: AnyObject) -> Bool {
        var current = element
        var visited = Set<ObjectIdentifier>()

        for _ in 0..<4 {
            let currentID = ObjectIdentifier(current)
            guard visited.insert(currentID).inserted else { return false }
            guard let parent = accessibilityInspector.parentElement(of: current) else { return false }

            if isTextInputElement(parent) {
                return true
            }

            current = parent
        }

        return false
    }

    private func hasTextInputDescendant(of element: AnyObject) -> Bool {
        var visited = Set<ObjectIdentifier>()
        return hasTextInputDescendant(of: element, remainingDepth: 3, visited: &visited)
    }

    private func hasTextInputDescendant(
        of element: AnyObject,
        remainingDepth: Int,
        visited: inout Set<ObjectIdentifier>
    ) -> Bool {
        guard remainingDepth > 0 else { return false }

        let elementID = ObjectIdentifier(element)
        guard visited.insert(elementID).inserted else { return false }

        for child in accessibilityInspector.childElements(of: element).prefix(40) {
            if isTextInputElement(child) {
                return true
            }

            if hasTextInputDescendant(of: child, remainingDepth: remainingDepth - 1, visited: &visited) {
                return true
            }
        }

        return false
    }
}
