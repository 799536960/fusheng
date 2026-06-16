import AppKit
import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
    static let voiceInput = Self("voiceInput")
}

struct SettingsView: View {
    @State private var settings = SettingsStore()
    @State private var apiKey = ""
    @State private var keychainMessage = ""

    private let keychain = KeychainService()

    var body: some View {
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

            Section("快捷键") {
                LabeledContent("语音输入") {
                    ShortcutRecorderField(name: .voiceInput)
                        .frame(width: 260)
                }
                Text("必须同时按下修饰键和普通键，例如 Control + Space 或 Command + Shift + V；单独字母、数字或单独修饰键不会被记录。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("触发方式", selection: Binding(get: { settings.triggerMode }, set: { settings.triggerMode = $0 })) {
                    ForEach(TriggerMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
            }

            Section("输出") {
                Toggle("自动粘贴到当前输入框", isOn: Binding(get: { settings.autoPasteEnabled }, set: { settings.autoPasteEnabled = $0 }))
                Toggle("粘贴后恢复剪贴板", isOn: Binding(get: { settings.restoreClipboardEnabled }, set: { settings.restoreClipboardEnabled = $0 }))
                Toggle("保留历史草稿", isOn: Binding(get: { settings.keepDraftHistoryEnabled }, set: { settings.keepDraftHistoryEnabled = $0 }))
            }
        }
        .padding()
        .onAppear {
            apiKey = (try? keychain.loadAPIKey()) ?? ""
        }
    }

    private func saveAPIKey() {
        do {
            try keychain.saveAPIKey(apiKey)
            keychainMessage = "API Key 已保存"
        } catch {
            keychainMessage = error.localizedDescription
        }
    }
}

private struct ShortcutRecorderField: NSViewRepresentable {
    let name: KeyboardShortcuts.Name

    func makeNSView(context: Context) -> KeyboardShortcuts.RecorderCocoa {
        let recorder = KeyboardShortcuts.RecorderCocoa(for: name)
        recorder.toolTip = tooltip
        return recorder
    }

    func updateNSView(_ recorder: KeyboardShortcuts.RecorderCocoa, context: Context) {
        recorder.shortcutName = name
        recorder.toolTip = tooltip
    }

    private var tooltip: String {
        "必须同时按下修饰键和普通键，例如 Control + Space 或 Command + Shift + V；单独字母、数字或单独修饰键不会被记录。"
    }
}
