import Foundation
import XCTest
@testable import Fusheng

final class FocusDetectorTests: XCTestCase {
    func testUntrustedAccessibilityReportsPermissionMissingForFrontmostApp() {
        let inspector = FakeAccessibilityInspector(isTrusted: false)
        let detector = FocusDetector(accessibilityInspector: inspector, appNameProvider: { "Notes" })

        XCTAssertEqual(detector.focusedInputContext(), .accessibilityPermissionMissing(appName: "Notes"))
    }

    func testMissingFocusedElementReportsNoInput() {
        let inspector = FakeAccessibilityInspector(isTrusted: true, element: nil)
        let detector = FocusDetector(accessibilityInspector: inspector, appNameProvider: { "Mail" })

        XCTAssertEqual(detector.focusedInputContext(), .noInput(appName: "Mail"))
    }

    func testTextFieldRoleReportsInputAvailable() {
        let element = NSObject()
        let inspector = FakeAccessibilityInspector(isTrusted: true, element: element, role: "AXTextField")
        let detector = FocusDetector(accessibilityInspector: inspector, appNameProvider: { "Safari" })

        XCTAssertEqual(detector.focusedInputContext(), .inputAvailable(appName: "Safari"))
    }

    func testSelectedTextRangeReportsInputAvailableWhenRoleIsNotTextRole() {
        let element = NSObject()
        let inspector = FakeAccessibilityInspector(
            isTrusted: true,
            element: element,
            role: "AXGroup",
            hasSelectedTextRange: true
        )
        let detector = FocusDetector(accessibilityInspector: inspector, appNameProvider: { "Xcode" })

        XCTAssertEqual(detector.focusedInputContext(), .inputAvailable(appName: "Xcode"))
    }

    func testTextRoleParentReportsInputAvailableWhenFocusedElementIsInternalNode() {
        let parent = NSObject()
        let child = NSObject()
        let inspector = FakeAccessibilityInspector(
            isTrusted: true,
            element: child,
            roles: [
                ObjectIdentifier(child): "AXStaticText",
                ObjectIdentifier(parent): "AXTextArea"
            ],
            parents: [
                ObjectIdentifier(child): parent
            ]
        )
        let detector = FocusDetector(accessibilityInspector: inspector, appNameProvider: { "Codex" })

        XCTAssertEqual(detector.focusedInputContext(), .inputAvailable(appName: "Codex"))
    }

    func testTextRoleChildReportsInputAvailableWhenFocusedElementIsContainer() {
        let container = NSObject()
        let child = NSObject()
        let inspector = FakeAccessibilityInspector(
            isTrusted: true,
            element: container,
            roles: [
                ObjectIdentifier(container): "AXGroup",
                ObjectIdentifier(child): "AXTextField"
            ],
            children: [
                ObjectIdentifier(container): [child]
            ]
        )
        let detector = FocusDetector(accessibilityInspector: inspector, appNameProvider: { "Codex" })

        XCTAssertEqual(detector.focusedInputContext(), .inputAvailable(appName: "Codex"))
    }

    func testNonTextRoleWithoutSelectedTextRangeReportsNoInput() {
        let element = NSObject()
        let inspector = FakeAccessibilityInspector(
            isTrusted: true,
            element: element,
            role: "AXButton",
            hasSelectedTextRange: false
        )
        let detector = FocusDetector(accessibilityInspector: inspector, appNameProvider: { "Finder" })

        XCTAssertEqual(detector.focusedInputContext(), .noInput(appName: "Finder"))
    }
}

private struct FakeAccessibilityInspector: AccessibilityInspecting {
    let isTrusted: Bool
    let element: AnyObject?
    let role: String?
    let roles: [ObjectIdentifier: String]
    let hasSelectedTextRange: Bool
    let parents: [ObjectIdentifier: AnyObject]
    let children: [ObjectIdentifier: [AnyObject]]

    init(
        isTrusted: Bool,
        element: AnyObject? = nil,
        role: String? = nil,
        roles: [ObjectIdentifier: String] = [:],
        hasSelectedTextRange: Bool = false,
        parents: [ObjectIdentifier: AnyObject] = [:],
        children: [ObjectIdentifier: [AnyObject]] = [:]
    ) {
        self.isTrusted = isTrusted
        self.element = element
        self.role = role
        self.roles = roles
        self.hasSelectedTextRange = hasSelectedTextRange
        self.parents = parents
        self.children = children
    }

    func isProcessTrusted(prompt: Bool) -> Bool {
        isTrusted
    }

    func focusedElement() -> AnyObject? {
        element
    }

    func role(of element: AnyObject) -> String? {
        roles[ObjectIdentifier(element)] ?? role
    }

    func hasSelectedTextRange(_ element: AnyObject) -> Bool {
        hasSelectedTextRange
    }

    func parentElement(of element: AnyObject) -> AnyObject? {
        parents[ObjectIdentifier(element)]
    }

    func childElements(of element: AnyObject) -> [AnyObject] {
        children[ObjectIdentifier(element)] ?? []
    }
}
