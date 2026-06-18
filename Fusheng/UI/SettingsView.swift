import AppKit
import AVFoundation
import OSLog
import SwiftUI

private let settingsLogger = Logger(subsystem: "com.fusheng.voiceinput", category: "Settings")

private enum SettingsSectionID: Hashable {
    case basics
    case polishStrategy
}

struct SettingsView: View {
    @State private var settings = SettingsStore()
    @State private var holdKey = SettingsStore().holdKey
    @State private var apiKey = ""
    @State private var keychainMessage = ""
    @State private var savedAPIKeySuffix: String?
    @State private var didLoadSavedAPIKey = false
    @State private var microphonePermissionStatus = MicrophonePermissionStatus.current
    @State private var selectedSection: SettingsSectionID = .basics
    @AppStorage("autoPasteEnabled") private var autoPasteEnabled = true
    @AppStorage("restoreClipboardEnabled") private var restoreClipboardEnabled = true
    @AppStorage("keepDraftHistoryEnabled") private var keepDraftHistoryEnabled = true

    private let keychain = KeychainService()

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedSection) {
                Text("基础设置")
                    .tag(SettingsSectionID.basics)
                Text("整理策略")
                    .tag(SettingsSectionID.polishStrategy)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } detail: {
            switch selectedSection {
            case .basics:
                basicsView
            case .polishStrategy:
                PolishStrategySettingsView()
            }
        }
        .frame(minWidth: 860, minHeight: 680)
        .onAppear {
            holdKey = settings.holdKey
            loadSavedAPIKey()
            refreshMicrophonePermissionStatus()
            clearKeyboardFocus()
        }
    }

    private var basicsView: some View {
        Form {
            Section("阿里百炼") {
                SecureField("API Key", text: $apiKey)

                Button("保存 API Key") {
                    saveAPIKey()
                }

                if !keychainMessage.isEmpty {
                    Text(keychainMessage)
                        .foregroundStyle(.secondary)
                }

                if let savedAPIKeySuffix {
                    Text("当前已保存 API Key 末尾 \(savedAPIKeySuffix)")
                        .foregroundStyle(.secondary)
                }
            }

            Section("模型") {
                TextField("ASR 模型", text: Binding(get: { settings.asrModel }, set: { settings.asrModel = $0 }))
                TextField("整理模型", text: Binding(get: { settings.polishModel }, set: { settings.polishModel = $0 }))

                Picker("整理模式", selection: Binding(get: { settings.polishMode }, set: { settings.polishMode = $0 })) {
                    ForEach(TextPolishMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
            }

            Section("权限") {
                LabeledContent("麦克风") {
                    Text(microphonePermissionStatus.displayName)
                        .foregroundStyle(microphonePermissionStatus.foregroundColor)
                }

                Text(microphonePermissionStatus.guidanceText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    if microphonePermissionStatus == .notDetermined {
                        Button("请求麦克风权限") {
                            requestMicrophonePermission()
                        }
                    }

                    if microphonePermissionStatus.shouldOpenSettings {
                        Button("打开麦克风权限设置") {
                            openMicrophoneSettings()
                        }
                    }

                    Button("刷新权限状态") {
                        refreshMicrophonePermissionStatus()
                    }
                }
            }

            Section("快捷键") {
                HotkeyRecorderButton(hotkey: $holdKey) { hotkey in
                    settings.holdKey = hotkey
                }
                Button("打开权限设置") {
                    openAccessibilitySettings()
                }
                Text("点击后按下任意单键完成录入；之后按住所选键开始说话，松开后自动整理。若当前焦点在输入框则写回输入框，否则按输出设置复制到剪贴板并保存草稿。若按键无反应，请在系统设置 > 隐私与安全性 > 辅助功能/输入监控中允许浮声。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("输出") {
                Toggle("无输入框时复制到剪贴板", isOn: $autoPasteEnabled)
                Toggle("粘贴后恢复剪贴板", isOn: $restoreClipboardEnabled)
                Toggle("保留历史草稿", isOn: $keepDraftHistoryEnabled)
            }
        }
        .padding()
    }

    private func loadSavedAPIKey() {
        guard !didLoadSavedAPIKey else { return }
        didLoadSavedAPIKey = true

        do {
            guard let savedAPIKey = try keychain.loadAPIKey(), !savedAPIKey.isEmpty else { return }
            apiKey = savedAPIKey
            savedAPIKeySuffix = String(savedAPIKey.suffix(4))
            keychainMessage = "API Key 已加载"
        } catch {
            keychainMessage = error.localizedDescription
        }
    }

    private func saveAPIKey() {
        do {
            try keychain.saveAPIKey(apiKey)
            savedAPIKeySuffix = String(apiKey.suffix(4))
            keychainMessage = "API Key 已保存"
        } catch {
            keychainMessage = error.localizedDescription
        }
    }

    private func openAccessibilitySettings() {
        _ = SystemAccessibilityInspector().isProcessTrusted(prompt: true)

        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func requestMicrophonePermission() {
        AVCaptureDevice.requestAccess(for: .audio) { _ in
            Task { @MainActor in
                refreshMicrophonePermissionStatus()
            }
        }
    }

    private func refreshMicrophonePermissionStatus() {
        microphonePermissionStatus = .current
    }

    private func openMicrophoneSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func clearKeyboardFocus() {
        DispatchQueue.main.async {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
    }
}

private enum MicrophonePermissionStatus: Equatable {
    case authorized
    case notDetermined
    case denied
    case restricted
    case unknown

    static var current: MicrophonePermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .authorized
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .unknown
        }
    }

    var displayName: String {
        switch self {
        case .authorized:
            return "已授权"
        case .notDetermined:
            return "未请求"
        case .denied:
            return "未授权"
        case .restricted:
            return "受限制"
        case .unknown:
            return "未知"
        }
    }

    var guidanceText: String {
        switch self {
        case .authorized:
            return "麦克风权限已开启，可以进行语音识别。"
        case .notDetermined:
            return "还没有请求麦克风权限。点击“请求麦克风权限”，在系统弹窗中允许浮声使用麦克风。"
        case .denied:
            return "麦克风权限未开启。请点击“打开麦克风权限设置”，在系统设置中允许浮声使用麦克风。"
        case .restricted:
            return "麦克风权限被系统限制，请在系统设置中检查麦克风权限。"
        case .unknown:
            return "无法确认麦克风权限状态，请打开系统设置检查麦克风权限。"
        }
    }

    var foregroundColor: Color {
        switch self {
        case .authorized:
            return .secondary
        case .notDetermined, .denied, .restricted, .unknown:
            return .red
        }
    }

    var shouldOpenSettings: Bool {
        switch self {
        case .authorized:
            return false
        case .notDetermined, .denied, .restricted, .unknown:
            return true
        }
    }
}

private struct HotkeyRecorderButton: View {
    @Binding var hotkey: SpeechHotkey
    let onChange: (SpeechHotkey) -> Void

    @StateObject private var recorder: HotkeyRecorderState

    init(hotkey: Binding<SpeechHotkey>, onChange: @escaping (SpeechHotkey) -> Void) {
        self._hotkey = hotkey
        self.onChange = onChange
        self._recorder = StateObject(
            wrappedValue: HotkeyRecorderState(initialHotkey: hotkey.wrappedValue) { recordedHotkey in
                hotkey.wrappedValue = recordedHotkey
                onChange(recordedHotkey)
            }
        )
    }

    var body: some View {
        Button {
            NSApp.keyWindow?.makeFirstResponder(nil)
            settingsLogger.info("hotkey recorder button clicked; clearing first responder and beginning capture")
            DiagnosticLog.write(category: "Settings", message: "hotkey recorder button clicked; clearing first responder and beginning capture")
            recorder.beginRecording()
        } label: {
            HStack {
                Text("长按触发键")
                    .foregroundStyle(.primary)
                Spacer()
                Text(recorder.isRecording ? "按下任意单键" : recorder.hotkey.displayName)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color(nsColor: .separatorColor))
                    )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("长按触发键，\(recorder.isRecording ? "按下任意单键" : recorder.hotkey.displayName)")
        .accessibilityAddTraits(.isButton)
        .background(
            HotkeyKeyCaptureView(isActive: recorder.isRecording) { event in
                recorder.record(event: event)
            }
            .frame(width: 1, height: 1)
            .accessibilityHidden(true)
        )
        .onAppear {
            recorder.sync(hotkey: hotkey)
        }
        .onDisappear {
            recorder.cancelRecording()
        }
        .onChange(of: hotkey) { _, newValue in
            recorder.sync(hotkey: newValue)
        }
    }
}

@MainActor
final class HotkeyRecorderState: ObservableObject {
    @Published private(set) var hotkey: SpeechHotkey
    @Published private(set) var isRecording = false

    private let onChange: (SpeechHotkey) -> Void

    init(initialHotkey: SpeechHotkey, onChange: @escaping (SpeechHotkey) -> Void) {
        self.hotkey = initialHotkey
        self.onChange = onChange
    }

    func beginRecording() {
        settingsLogger.info("hotkey recorder state began capture currentKeyCode=\(self.hotkey.keyCode, privacy: .public) currentDisplayName=\(self.hotkey.displayName, privacy: .public)")
        DiagnosticLog.write(category: "Settings", message: "hotkey recorder state began capture currentKeyCode=\(hotkey.keyCode) currentDisplayName=\(hotkey.displayName)")
        isRecording = true
    }

    func cancelRecording() {
        if isRecording {
            settingsLogger.info("hotkey recorder state canceled capture")
            DiagnosticLog.write(category: "Settings", message: "hotkey recorder state canceled capture")
        }
        isRecording = false
    }

    func record(event: NSEvent) {
        record(hotkey: SpeechHotkey.from(event: event))
    }

    func record(hotkey recordedHotkey: SpeechHotkey) {
        settingsLogger.info("hotkey recorder state recorded keyCode=\(recordedHotkey.keyCode, privacy: .public) displayName=\(recordedHotkey.displayName, privacy: .public)")
        DiagnosticLog.write(category: "Settings", message: "hotkey recorder state recorded keyCode=\(recordedHotkey.keyCode) displayName=\(recordedHotkey.displayName)")
        hotkey = recordedHotkey
        isRecording = false
        onChange(recordedHotkey)
    }

    func sync(hotkey currentHotkey: SpeechHotkey) {
        guard hotkey != currentHotkey else { return }
        hotkey = currentHotkey
    }
}

private struct HotkeyKeyCaptureView: NSViewRepresentable {
    let isActive: Bool
    let onKeyDown: (NSEvent) -> Void

    func makeNSView(context: Context) -> KeyCaptureNSView {
        let view = KeyCaptureNSView()
        view.onKeyDown = onKeyDown
        return view
    }

    func updateNSView(_ nsView: KeyCaptureNSView, context: Context) {
        nsView.onKeyDown = onKeyDown
        nsView.setCapturing(isActive)

        if isActive {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        } else if nsView.window?.firstResponder === nsView {
            nsView.window?.makeFirstResponder(nil)
        }
    }

    final class KeyCaptureNSView: NSView {
        var onKeyDown: ((NSEvent) -> Void)?
        private var localMonitor: Any?
        private var isCapturing = false

        override var acceptsFirstResponder: Bool {
            true
        }

        deinit {
            removeLocalMonitor()
        }

        func setCapturing(_ isCapturing: Bool) {
            guard self.isCapturing != isCapturing else { return }
            self.isCapturing = isCapturing

            if isCapturing {
                installLocalMonitorIfNeeded()
                settingsLogger.info("hotkey capture view enabled local monitor")
                DiagnosticLog.write(category: "Settings", message: "hotkey capture view enabled local monitor")
            } else {
                removeLocalMonitor()
                settingsLogger.info("hotkey capture view disabled local monitor")
                DiagnosticLog.write(category: "Settings", message: "hotkey capture view disabled local monitor")
            }

            NotificationCenter.default.post(
                name: .hotkeyRecorderCaptureDidChange,
                object: nil,
                userInfo: ["isCapturing": isCapturing]
            )
        }

        override func keyDown(with event: NSEvent) {
            handleKeyDown(event)
        }

        private func installLocalMonitorIfNeeded() {
            guard localMonitor == nil else { return }

            localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                guard self.window?.isKeyWindow == true else { return event }
                self.handleKeyDown(event)
                return nil
            }
        }

        private func removeLocalMonitor() {
            if let localMonitor {
                NSEvent.removeMonitor(localMonitor)
                self.localMonitor = nil
            }
        }

        private func handleKeyDown(_ event: NSEvent) {
            guard !event.isARepeat else {
                settingsLogger.info("hotkey capture view ignored repeated keyDown keyCode=\(event.keyCode, privacy: .public)")
                DiagnosticLog.write(category: "Settings", message: "hotkey capture view ignored repeated keyDown keyCode=\(event.keyCode)")
                return
            }
            settingsLogger.info("hotkey capture view captured keyDown keyCode=\(event.keyCode, privacy: .public)")
            DiagnosticLog.write(category: "Settings", message: "hotkey capture view captured keyDown keyCode=\(event.keyCode)")
            onKeyDown?(event)
        }
    }
}
