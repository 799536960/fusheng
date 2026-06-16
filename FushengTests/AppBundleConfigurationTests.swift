import AppKit
import XCTest

final class AppBundleConfigurationTests: XCTestCase {
    func testInfoPlistDefinesLaunchableBundleMetadata() throws {
        let infoPlist = projectRoot.appending(path: "Fusheng/Resources/Info.plist")
        let data = try Data(contentsOf: infoPlist)
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])

        XCTAssertEqual(plist["CFBundleExecutable"] as? String, "$(EXECUTABLE_NAME)")
        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, "$(PRODUCT_BUNDLE_IDENTIFIER)")
        XCTAssertEqual(plist["CFBundleName"] as? String, "$(PRODUCT_NAME)")
        XCTAssertEqual(plist["CFBundlePackageType"] as? String, "APPL")
    }

    func testRootMenuUsesOpenSettingsAndActivatesTheApp() throws {
        let source = try String(
            contentsOf: projectRoot.appending(path: "Fusheng/UI/RootMenuContent.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("@Environment(\\.openSettings)"))
        XCTAssertTrue(source.contains("openSettings()"))
        XCTAssertTrue(source.contains("NSApp.activate()"))
        XCTAssertTrue(source.contains("makeKeyAndOrderFront(nil)"))
        XCTAssertTrue(source.contains("orderFrontRegardless()"))
        XCTAssertTrue(source.contains("DispatchQueue.main.asyncAfter"))
        XCTAssertFalse(source.contains("showSettingsWindow"))
        XCTAssertFalse(source.contains("activate(ignoringOtherApps: true)"))
        XCTAssertFalse(source.contains("SettingsLink"))
    }

    func testAppIconAssetCatalogIsConfiguredAsAResource() throws {
        let iconContents = projectRoot.appending(path: "Fusheng/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: iconContents.path))

        let iconData = try Data(contentsOf: iconContents)
        let iconJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: iconData) as? [String: Any])
        let images = try XCTUnwrap(iconJSON["images"] as? [[String: String]])
        XCTAssertTrue(images.contains { image in
            image["idiom"] == "mac"
                && image["size"] == "512x512"
                && image["scale"] == "2x"
                && image["filename"] == "AppIcon-512@2x.png"
        })
        let highResolutionIcon = iconContents.deletingLastPathComponent().appending(path: "AppIcon-512@2x.png")
        let iconRep = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: highResolutionIcon)))
        XCTAssertEqual(iconRep.pixelsWide, 1024)
        XCTAssertEqual(iconRep.pixelsHigh, 1024)

        let project = try String(
            contentsOf: projectRoot.appending(path: "Fusheng.xcodeproj/project.pbxproj"),
            encoding: .utf8
        )
        XCTAssertTrue(project.contains("Assets.xcassets"))
        XCTAssertTrue(project.contains("Assets.xcassets in Resources"))
        XCTAssertTrue(project.contains("PBXResourcesBuildPhase"))
    }

    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
