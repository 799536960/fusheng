import AppKit
import XCTest

final class AppBundleConfigurationTests: XCTestCase {
    func testInfoPlistDefinesMenuBarOnlyBundleMetadata() throws {
        let infoPlist = try sourceSnapshotURL("Fusheng/Resources/Info.plist")
        let data = try Data(contentsOf: infoPlist)
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])

        XCTAssertEqual(plist["CFBundleExecutable"] as? String, "$(EXECUTABLE_NAME)")
        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, "$(PRODUCT_BUNDLE_IDENTIFIER)")
        XCTAssertEqual(plist["CFBundleName"] as? String, "$(PRODUCT_NAME)")
        XCTAssertEqual(plist["CFBundlePackageType"] as? String, "APPL")
        XCTAssertEqual(plist["CFBundleLocalizations"] as? [String], ["zh-Hans"])
        XCTAssertEqual(plist["LSUIElement"] as? Bool, true)
    }

    func testRootMenuUsesExplicitSettingsWindowController() throws {
        let source = try String(
            contentsOf: try sourceSnapshotURL("Fusheng/UI/RootMenuContent.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("Button(\"打开设置\")"))
        XCTAssertTrue(source.contains("SettingsWindowController.shared.show()"))
        XCTAssertFalse(source.contains("@Environment(\\.openSettings)"))
        XCTAssertFalse(source.contains("openSettings()"))
        XCTAssertFalse(source.contains("showSettingsWindow"))
        XCTAssertFalse(source.contains("SettingsLink"))
    }

    func testRootMenuOpensDraftHistoryRefreshesAndActivatesWindow() throws {
        let source = try String(
            contentsOf: try sourceSnapshotURL("Fusheng/UI/RootMenuContent.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("openDraftHistoryWindow()"))
        XCTAssertTrue(source.contains("NotificationCenter.default.post(name: .draftHistoryDidChange"))
        XCTAssertTrue(source.contains("bringWindowToFront(matching:"))
        XCTAssertTrue(source.contains("草稿历史"))
    }

    func testRootMenuOpensFailedRecordingWindowRefreshesAndActivatesWindow() throws {
        let source = try String(
            contentsOf: try sourceSnapshotURL("Fusheng/UI/RootMenuContent.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("Button(\"打开失败录音\""))
        XCTAssertTrue(source.contains("openFailedRecordingWindow()"))
        XCTAssertTrue(source.contains("NotificationCenter.default.post(name: .failedRecordingQueueDidChange"))
        XCTAssertTrue(source.contains("bringWindowToFront(matching:"))
        XCTAssertTrue(source.contains("失败录音"))
    }

    func testAppCreatesFailedRecordingWindowAndModelContainer() throws {
        let source = try String(
            contentsOf: try sourceSnapshotURL("Fusheng/App/FushengApp.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("ModelContainer(for: DraftRecord.self, FailedRecordingRecord.self)"))
        XCTAssertTrue(source.contains("Window(\"失败录音\", id: \"failed-recordings\")"))
        XCTAssertTrue(source.contains("FailedRecordingView("))
        XCTAssertTrue(source.contains("FailedRecordingStore("))
        XCTAssertTrue(source.contains("FailedRecordingRetryService("))
    }

    func testMenuBarExtraUsesDedicatedTemplateAssetForStatusBarIcon() throws {
        let source = try String(
            contentsOf: try sourceSnapshotURL("Fusheng/App/FushengApp.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("MenuBarExtra"))
        XCTAssertTrue(source.contains("Image(nsImage: Self.menuBarIconImage)"))
        XCTAssertTrue(source.contains("NSImage(named: \"MenuBarIcon\")"))
        XCTAssertTrue(source.contains(".renderingMode(.template)"))
        XCTAssertTrue(source.contains("image.isTemplate = true"))
        XCTAssertTrue(source.contains(".frame(width: 18, height: 18)"))
        XCTAssertTrue(source.contains(".accessibilityLabel(\"浮声\")"))
        XCTAssertFalse(source.contains("Label(\"浮声\", systemImage: coordinator.menuBarSystemImage)"))
        XCTAssertFalse(source.contains("NSApplication.shared.applicationIconImage"))
        XCTAssertFalse(source.contains(".renderingMode(.original)"))
        XCTAssertFalse(source.contains("image.isTemplate = false"))
    }

    func testMenuBarIconAssetIsTransparentTemplateArtwork() throws {
        let contentsURL = try sourceSnapshotURL("Fusheng/Resources/Assets.xcassets/MenuBarIcon.imageset/Contents.json")
        let data = try Data(contentsOf: contentsURL)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let properties = try XCTUnwrap(json["properties"] as? [String: String])
        XCTAssertEqual(properties["template-rendering-intent"], "template")

        let images = try XCTUnwrap(json["images"] as? [[String: String]])
        XCTAssertTrue(images.contains { image in
            image["idiom"] == "universal"
                && image["scale"] == "2x"
                && image["filename"] == "MenuBarIcon@2x.png"
        })

        let retinaIcon = contentsURL.deletingLastPathComponent().appending(path: "MenuBarIcon@2x.png")
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: retinaIcon)))
        XCTAssertEqual(bitmap.pixelsWide, 36)
        XCTAssertEqual(bitmap.pixelsHigh, 36)

        let totalPixels = bitmap.pixelsWide * bitmap.pixelsHigh
        var transparentPixels = 0
        var opaquePixels = 0

        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                let alpha = bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0
                if alpha < 0.05 {
                    transparentPixels += 1
                } else if alpha > 0.95 {
                    opaquePixels += 1
                }
            }
        }

        XCTAssertGreaterThan(transparentPixels, totalPixels / 2)
        XCTAssertGreaterThan(opaquePixels, 80)
        XCTAssertLessThan(opaquePixels, totalPixels / 2)
        XCTAssertLessThan(bitmap.colorAt(x: 0, y: 0)?.alphaComponent ?? 1, 0.05)
        XCTAssertLessThan(bitmap.colorAt(x: 35, y: 35)?.alphaComponent ?? 1, 0.05)
    }

    func testFailedRecordingViewShowsRetryAndDeleteActions() throws {
        let source = try String(
            contentsOf: try sourceSnapshotURL("Fusheng/UI/FailedRecordingView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("struct FailedRecordingView"))
        XCTAssertTrue(source.contains("重新请求"))
        XCTAssertTrue(source.contains("删除"))
        XCTAssertTrue(source.contains("音频文件缺失"))
        XCTAssertTrue(source.contains(".failedRecordingQueueDidChange"))
        XCTAssertTrue(source.contains("retryService.retry"))
    }

    func testSettingsViewUsesCustomSingleKeyRecorder() throws {
        let source = try String(
            contentsOf: try sourceSnapshotURL("Fusheng/UI/SettingsView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("HotkeyRecorderButton"))
        XCTAssertTrue(source.contains("按下任意单键"))
        XCTAssertTrue(source.contains("settings.holdKey = hotkey"))
        XCTAssertTrue(source.contains(".frame(maxWidth: .infinity"))
        XCTAssertTrue(source.contains("Button {"))
        XCTAssertTrue(source.contains(".buttonStyle(.plain)"))
        XCTAssertFalse(source.contains(".onTapGesture"))
        XCTAssertTrue(source.contains(".accessibilityAddTraits(.isButton)"))
        XCTAssertTrue(source.contains("HotkeyKeyCaptureView"))
        XCTAssertTrue(source.contains("makeFirstResponder(nsView)"))
        XCTAssertTrue(source.contains("NSApp.keyWindow?.makeFirstResponder(nil)"))
        XCTAssertTrue(source.contains("override func keyDown(with event: NSEvent)"))
        XCTAssertTrue(source.contains("NSEvent.addLocalMonitorForEvents(matching: .keyDown"))
        XCTAssertTrue(source.contains(".hotkeyRecorderCaptureDidChange"))
        XCTAssertTrue(source.contains("SpeechHotkey.from(event: event)"))
        XCTAssertTrue(source.contains("Button(\"打开权限设置\")"))
        XCTAssertTrue(source.contains("openAccessibilitySettings()"))
        XCTAssertTrue(source.contains("Privacy_Accessibility"))
        XCTAssertTrue(source.contains("辅助功能/输入监控中允许浮声"))
        XCTAssertFalse(source.contains("KeyboardShortcuts.Recorder(\"语音输入\""))
        XCTAssertFalse(source.contains("Picker(\"长按触发键\""))
        XCTAssertFalse(source.contains("Picker(\"触发方式\""))
    }

    func testSettingsViewLoadsSavedAPIKeyOnAppear() throws {
        let source = try String(
            contentsOf: try sourceSnapshotURL("Fusheng/UI/SettingsView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("try keychain.saveAPIKey(apiKey)"))
        XCTAssertTrue(source.contains("SecureField(\"API Key\", text: $apiKey)"))
        XCTAssertTrue(source.contains("loadSavedAPIKey()"))
        XCTAssertTrue(source.contains("try keychain.loadAPIKey()"))
        XCTAssertTrue(source.contains("apiKey = savedAPIKey"))
        XCTAssertTrue(source.contains("savedAPIKeySuffix"))
        XCTAssertTrue(source.contains("API Key 已加载"))
    }

    func testSettingsViewShowsMicrophonePermissionStatusAndActions() throws {
        let source = try String(
            contentsOf: try sourceSnapshotURL("Fusheng/UI/SettingsView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("import AVFoundation"))
        XCTAssertTrue(source.contains("Section(\"权限\")"))
        XCTAssertTrue(source.contains("LabeledContent(\"麦克风\")"))
        XCTAssertTrue(source.contains("MicrophonePermissionStatus.current"))
        XCTAssertTrue(source.contains("AVCaptureDevice.authorizationStatus(for: .audio)"))
        XCTAssertTrue(source.contains("AVCaptureDevice.requestAccess(for: .audio)"))
        XCTAssertTrue(source.contains("Button(\"请求麦克风权限\")"))
        XCTAssertTrue(source.contains("Button(\"打开麦克风权限设置\")"))
        XCTAssertTrue(source.contains("Privacy_Microphone"))
        XCTAssertTrue(source.contains("Button(\"刷新权限状态\")"))
    }

    func testSettingsViewOutputTogglesUseAppStorageBindings() throws {
        let source = try String(
            contentsOf: try sourceSnapshotURL("Fusheng/UI/SettingsView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("@AppStorage(\"autoPasteEnabled\")"))
        XCTAssertTrue(source.contains("@AppStorage(\"restoreClipboardEnabled\")"))
        XCTAssertTrue(source.contains("@AppStorage(\"keepDraftHistoryEnabled\")"))
        XCTAssertTrue(source.contains("Toggle(\"无输入框时复制到剪贴板\", isOn: $autoPasteEnabled)"))
        XCTAssertTrue(source.contains("Toggle(\"粘贴后恢复剪贴板\", isOn: $restoreClipboardEnabled)"))
        XCTAssertTrue(source.contains("Toggle(\"保留历史草稿\", isOn: $keepDraftHistoryEnabled)"))
        XCTAssertFalse(source.contains("settings.autoPasteEnabled }, set: { settings.autoPasteEnabled"))
        XCTAssertFalse(source.contains("settings.restoreClipboardEnabled }, set: { settings.restoreClipboardEnabled"))
        XCTAssertFalse(source.contains("settings.keepDraftHistoryEnabled }, set: { settings.keepDraftHistoryEnabled"))
    }

    func testSettingsViewContainsPolishStrategyNavigation() throws {
        let source = try String(
            contentsOf: try sourceSnapshotURL("Fusheng/UI/SettingsView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("NavigationSplitView"))
        XCTAssertTrue(source.contains("基础设置"))
        XCTAssertTrue(source.contains("整理策略"))
        XCTAssertTrue(source.contains("PolishStrategySettingsView()"))
    }

    func testPolishStrategySettingsViewContainsEditorResetAndTestAreas() throws {
        let source = try String(
            contentsOf: try sourceSnapshotURL("Fusheng/UI/PolishStrategySettingsView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("struct PolishStrategySettingsView"))
        XCTAssertTrue(source.contains("固定安全边界"))
        XCTAssertTrue(source.contains("模式策略"))
        XCTAssertTrue(source.contains("额外约束"))
        XCTAssertTrue(source.contains("测试整理效果"))
        XCTAssertTrue(source.contains("保存策略"))
        XCTAssertTrue(source.contains("恢复当前模式默认"))
        XCTAssertTrue(source.contains("恢复全部默认"))
        XCTAssertTrue(source.contains("confirmationDialog"))
        XCTAssertTrue(source.contains("TextPolishPrompt.safetyBoundary"))
        XCTAssertTrue(source.contains("polisher.polish"))
        XCTAssertTrue(source.contains("settings.polishModel.trimmingCharacters(in: .whitespacesAndNewlines)"))
        XCTAssertTrue(source.contains("throw AppError.polishFailed(\"整理模型为空\")"))
        XCTAssertTrue(source.contains("throw AppError.missingAPIKey"))
        XCTAssertTrue(source.contains("loadedAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)"))
        XCTAssertTrue(source.contains("@State private var activeTestID"))
        XCTAssertTrue(source.contains("activeTestID = nil"))
        XCTAssertTrue(source.contains("guard activeTestID == testID else { return }"))
        XCTAssertTrue(source.contains("关闭时使用当前模式默认策略；打开后下面的普通选项、模式策略和额外约束会生效。"))
        XCTAssertEqual(source.components(separatedBy: ".disabled(!strategy.isCustomEnabled)").count - 1, 3)
        XCTAssertFalse(source.contains("copyToClipboard"))
        XCTAssertFalse(source.contains("saveDraft"))
    }

    func testHardenedRuntimeAllowsMicrophoneResourceAccess() throws {
        let entitlementsURL = try projectFileURL("Fusheng/Fusheng.entitlements")
        let entitlementsData = try Data(contentsOf: entitlementsURL)
        let entitlements = try XCTUnwrap(PropertyListSerialization.propertyList(from: entitlementsData, format: nil) as? [String: Any])
        let project = try String(
            contentsOf: try projectFileURL("Fusheng.xcodeproj/project.pbxproj"),
            encoding: .utf8
        )

        XCTAssertEqual(entitlements["com.apple.security.device.audio-input"] as? Bool, true)
        XCTAssertTrue(project.contains("ENABLE_HARDENED_RUNTIME = YES;"))
        XCTAssertTrue(project.contains("ENABLE_RESOURCE_ACCESS_AUDIO_INPUT = YES;"))
    }

    func testProjectYMLPreservesGeneratedProjectRequirements() throws {
        let source = try String(
            contentsOf: try projectFileURL("project.yml"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("ENABLE_RESOURCE_ACCESS_AUDIO_INPUT: YES"))
        XCTAssertTrue(source.contains("Copy source snapshot"))
        XCTAssertTrue(source.contains("Fusheng/App/FushengApp.swift"))
        XCTAssertTrue(source.contains("Fusheng/UI/RootMenuContent.swift"))
        XCTAssertTrue(source.contains("Fusheng/Resources/Assets.xcassets/MenuBarIcon.imageset"))
        XCTAssertTrue(source.contains("Fusheng.xcodeproj/project.pbxproj"))
    }

    func testAppStartsHotkeyServiceDuringInitialization() throws {
        let source = try String(
            contentsOf: try sourceSnapshotURL("Fusheng/App/FushengApp.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("private let hotkeyService: HotkeyService"))
        XCTAssertTrue(source.contains("service.start()"))
        XCTAssertFalse(source.contains(".task {\n                    startHotkeyServiceIfNeeded()"))
    }

    func testAppDoesNotOpenSettingsWindowFromInitialization() throws {
        let source = try String(
            contentsOf: try sourceSnapshotURL("Fusheng/App/FushengApp.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("if !Self.isRunningTests"))
        XCTAssertFalse(source.contains("scheduleInitialSettingsWindowOpen()"))
        XCTAssertFalse(source.contains("DispatchQueue.main.asyncAfter"))
        XCTAssertFalse(source.contains("SettingsWindowController.shared.show()"))
    }

    func testAppUsesOnlyManualSettingsWindowController() throws {
        let source = try String(
            contentsOf: try sourceSnapshotURL("Fusheng/App/FushengApp.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(source.contains("Settings {"))
        XCTAssertFalse(source.contains("SettingsView()"))
    }

    func testAppIconLaunchAndReopenShowSettingsWindow() throws {
        let appSource = try String(
            contentsOf: try sourceSnapshotURL("Fusheng/App/FushengApp.swift"),
            encoding: .utf8
        )
        let delegateSource = try String(
            contentsOf: try sourceSnapshotURL("Fusheng/App/AppLaunchDelegate.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(appSource.contains("@NSApplicationDelegateAdaptor(AppLaunchDelegate.self)"))
        XCTAssertTrue(delegateSource.contains("applicationDidFinishLaunching"))
        XCTAssertTrue(delegateSource.contains("applicationShouldHandleReopen"))
        XCTAssertTrue(delegateSource.contains("openSettingsWindow()"))
        XCTAssertTrue(delegateSource.contains("DispatchQueue.main.async"))
        XCTAssertTrue(delegateSource.contains("SettingsWindowController.shared.show()"))
        XCTAssertFalse(delegateSource.contains("showSettingsWindow:"))
    }

    func testSettingsWindowControllerHostsAndRaisesSettingsView() throws {
        let source = try String(
            contentsOf: try sourceSnapshotURL("Fusheng/App/SettingsWindowController.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("final class SettingsWindowController"))
        XCTAssertTrue(source.contains("static let shared"))
        XCTAssertTrue(source.contains("NSHostingController(rootView: SettingsView()"))
        XCTAssertFalse(source.contains("SettingsView().frame(width: 520, height: 520)"))
        XCTAssertTrue(source.contains(".resizable"))
        XCTAssertTrue(source.contains("window.contentMinSize = NSSize(width: 860, height: 680)"))
        XCTAssertTrue(source.contains("window.setContentSize(NSSize(width: 920, height: 720))"))
        XCTAssertTrue(source.contains("window.title = \"设置\""))
        XCTAssertFalse(source.contains("NSApp.setActivationPolicy(.regular)"))
        XCTAssertTrue(source.contains("NSApp.activate(ignoringOtherApps: true)"))
        XCTAssertTrue(source.contains("NSApp.activate()"))
        XCTAssertFalse(source.contains(".activateIgnoringOtherApps"))
        XCTAssertFalse(source.contains("window.level = .floating"))
        XCTAssertTrue(source.contains("makeKeyAndOrderFront(nil)"))
        XCTAssertTrue(source.contains("window.makeMain()"))
        XCTAssertTrue(source.contains("orderFrontRegardless()"))
        XCTAssertFalse(source.contains("window.delegate = self"))
        XCTAssertFalse(source.contains("windowWillClose"))
        XCTAssertFalse(source.contains("NSApp.setActivationPolicy(.accessory)"))
        XCTAssertFalse(source.contains("setActivationPolicy"))
    }

    func testHotkeyRegistererUsesEventTapToInterceptSingleKey() throws {
        let source = try String(
            contentsOf: try sourceSnapshotURL("Fusheng/Services/HotkeyService.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("CGEvent.tapCreate"))
        XCTAssertTrue(source.contains("CGEventType.keyDown"))
        XCTAssertTrue(source.contains("CGEventType.keyUp"))
        XCTAssertTrue(source.contains("return nil"))
    }

    func testHotkeyDiagnosticsTelemetryCoversCapturePath() throws {
        let hotkeySource = try String(
            contentsOf: try sourceSnapshotURL("Fusheng/Services/HotkeyService.swift"),
            encoding: .utf8
        )
        let coordinatorSource = try String(
            contentsOf: try projectFileURL("Fusheng/App/AppCoordinator.swift"),
            encoding: .utf8
        )
        let settingsSource = try String(
            contentsOf: try sourceSnapshotURL("Fusheng/UI/SettingsView.swift"),
            encoding: .utf8
        )
        let appSource = try String(
            contentsOf: try sourceSnapshotURL("Fusheng/App/FushengApp.swift"),
            encoding: .utf8
        )
        let diagnosticsScript = try String(
            contentsOf: try projectFileURL("script/hotkey_diagnostics.sh"),
            encoding: .utf8
        )

        XCTAssertTrue(hotkeySource.contains("category: \"Hotkey\""))
        XCTAssertTrue(hotkeySource.contains("capture health reason="))
        XCTAssertTrue(hotkeySource.contains("secureInput="))
        XCTAssertTrue(hotkeySource.contains("matched \\("))
        XCTAssertTrue(hotkeySource.contains("dispatching \\("))
        XCTAssertTrue(hotkeySource.contains("writeHotkeyDiagnostic"))
        XCTAssertTrue(coordinatorSource.contains("startRecording requested; state="))
        XCTAssertTrue(coordinatorSource.contains("startRecording microphone permission="))
        XCTAssertTrue(coordinatorSource.contains("startRecording focusContext="))
        XCTAssertTrue(coordinatorSource.contains("DiagnosticLog.write(category: \"Coordinator\""))
        XCTAssertTrue(settingsSource.contains("category: \"Settings\""))
        XCTAssertTrue(settingsSource.contains("hotkey capture view captured keyDown keyCode="))
        XCTAssertTrue(settingsSource.contains("DiagnosticLog.write(category: \"Settings\""))
        XCTAssertTrue(appSource.contains("hotkey onStart closure invoked"))
        XCTAssertTrue(appSource.contains("hotkey start task entered state="))
        XCTAssertTrue(appSource.contains("hotkey onFinish closure invoked"))
        XCTAssertTrue(appSource.contains("hotkey finish task entered state="))
        XCTAssertTrue(diagnosticsScript.contains("hotkey-diagnostics.log"))
        XCTAssertTrue(diagnosticsScript.contains("tail -n"))
        XCTAssertTrue(diagnosticsScript.contains("tail -F"))
    }

    func testRecordingOverlayUsesGeneratedMicrophoneImageAndWaveform() throws {
        let source = try String(
            contentsOf: try sourceSnapshotURL("Fusheng/UI/RecordingOverlayView.swift"),
            encoding: .utf8
        )
        let appSource = try String(
            contentsOf: try sourceSnapshotURL("Fusheng/App/FushengApp.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("GeneratedMicrophoneImage"))
        XCTAssertTrue(source.contains("AudioLevelWaveformView"))
        XCTAssertTrue(source.contains(".audioLevelDidChange"))
        XCTAssertTrue(source.contains("configureFloatingOverlayWindow"))
        XCTAssertTrue(source.contains("panel.ignoresMouseEvents = true"))
        XCTAssertTrue(source.contains("window.ignoresMouseEvents = true"))
        XCTAssertFalse(appSource.contains("Window(\"录音状态\""))
    }

    func testRecordingOverlayShowsThroughoutActiveWorkflow() throws {
        let source = try String(
            contentsOf: try projectFileURL("Fusheng/App/AppCoordinator.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("case .recording, .recognizing, .polishing, .delivering:\n            return true"))
        XCTAssertTrue(source.contains("case .idle, .completed, .failed:\n            return false"))
        XCTAssertFalse(source.contains("case .idle, .recognizing, .polishing, .delivering, .completed, .failed:\n            return false"))
    }

    func testAppIconAssetCatalogIsConfiguredAsAResource() throws {
        let iconContents = try sourceSnapshotURL("Fusheng/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json")
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
            contentsOf: try sourceSnapshotURL("Fusheng.xcodeproj/project.pbxproj"),
            encoding: .utf8
        )
        XCTAssertTrue(project.contains("Assets.xcassets"))
        XCTAssertTrue(project.contains("Assets.xcassets in Resources"))
        XCTAssertTrue(project.contains("PBXResourcesBuildPhase"))
    }

    func testMacAppUsesStableDevelopmentSigningInsteadOfAdHocSigning() throws {
        let project = try String(
            contentsOf: try sourceSnapshotURL("Fusheng.xcodeproj/project.pbxproj"),
            encoding: .utf8
        )

        XCTAssertTrue(project.contains("DEVELOPMENT_TEAM = 24482TH5FJ;"))
        XCTAssertTrue(project.contains("CODE_SIGN_IDENTITY = \"Apple Development\";"))
        XCTAssertFalse(project.contains("CODE_SIGN_IDENTITY = -;"))
        XCTAssertTrue(project.contains("ENABLE_HARDENED_RUNTIME = YES;"))
    }

    func testLocalPublishScriptPreventsDuplicateFushengInstances() throws {
        let script = try String(
            contentsOf: try projectFileURL("script/publish_local.sh"),
            encoding: .utf8
        )

        XCTAssertTrue(script.contains("stop_all_fusheng_processes"))
        XCTAssertTrue(script.contains("cleanup_on_exit"))
        XCTAssertTrue(script.contains("trap cleanup_on_exit EXIT"))
        XCTAssertTrue(script.contains("pkill -f \"$DERIVED_DATA_FUSHENG_PATTERN\""))
        XCTAssertTrue(script.contains("verify_only_installed_instance_is_running"))
        XCTAssertTrue(script.contains("unexpected extra Fusheng process"))
    }

    private func sourceSnapshotURL(
        _ path: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> URL {
        let resourceURL = try XCTUnwrap(
            Bundle(for: Self.self).resourceURL,
            "Missing test bundle resources",
            file: file,
            line: line
        )
        return resourceURL.appending(path: "SourceSnapshot").appending(path: path)
    }

    private func projectFileURL(
        _ path: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> URL {
        let snapshotURL = try sourceSnapshotURL(path, file: file, line: line)
        if FileManager.default.fileExists(atPath: snapshotURL.path) {
            return snapshotURL
        }

        let testFileURL = URL(filePath: String(describing: file))
        return testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: path)
    }
}
