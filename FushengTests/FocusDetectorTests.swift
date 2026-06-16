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
    let hasSelectedTextRange: Bool

    init(
        isTrusted: Bool,
        element: AnyObject? = nil,
        role: String? = nil,
        hasSelectedTextRange: Bool = false
    ) {
        self.isTrusted = isTrusted
        self.element = element
        self.role = role
        self.hasSelectedTextRange = hasSelectedTextRange
    }

    func isProcessTrusted(prompt: Bool) -> Bool {
        isTrusted
    }

    func focusedElement() -> AnyObject? {
        element
    }

    func role(of element: AnyObject) -> String? {
        role
    }

    func hasSelectedTextRange(_ element: AnyObject) -> Bool {
        hasSelectedTextRange
    }
}
