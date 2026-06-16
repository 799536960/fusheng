import AppKit
import XCTest

final class AppBundleConfigurationTests: XCTestCase {
    func testRootMenuUsesSwiftUISettingsLink() throws {
        let source = try String(
            contentsOf: projectRoot.appending(path: "Fusheng/UI/RootMenuContent.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("SettingsLink"))
        XCTAssertFalse(source.contains("showSettingsWindow"))
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
