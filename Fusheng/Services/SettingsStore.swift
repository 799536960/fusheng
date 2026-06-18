import Foundation

struct SettingsStore: SettingsProviding {
    private enum Key {
        static let triggerMode = "triggerMode"
        static let asrModel = "asrModel"
        static let polishModel = "polishModel"
        static let polishMode = "polishMode"
        static let autoPasteEnabled = "autoPasteEnabled"
        static let restoreClipboardEnabled = "restoreClipboardEnabled"
        static let keepDraftHistoryEnabled = "keepDraftHistoryEnabled"

        static func polishStrategy(_ mode: TextPolishMode) -> String {
            "polishStrategy.\(mode.rawValue)"
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var triggerMode: TriggerMode {
        get { TriggerMode(rawValue: defaults.string(forKey: Key.triggerMode) ?? "") ?? .toggle }
        set { defaults.set(newValue.rawValue, forKey: Key.triggerMode) }
    }

    var asrModel: String {
        get { defaults.string(forKey: Key.asrModel) ?? "fun-asr-realtime" }
        set { defaults.set(newValue, forKey: Key.asrModel) }
    }

    var polishModel: String {
        get { defaults.string(forKey: Key.polishModel) ?? "qwen-plus" }
        set { defaults.set(newValue, forKey: Key.polishModel) }
    }

    var polishMode: TextPolishMode {
        get { TextPolishMode(rawValue: defaults.string(forKey: Key.polishMode) ?? "") ?? .clean }
        set { defaults.set(newValue.rawValue, forKey: Key.polishMode) }
    }

    var autoPasteEnabled: Bool {
        get { defaults.object(forKey: Key.autoPasteEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.autoPasteEnabled) }
    }

    var restoreClipboardEnabled: Bool {
        get { defaults.object(forKey: Key.restoreClipboardEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.restoreClipboardEnabled) }
    }

    var keepDraftHistoryEnabled: Bool {
        get { defaults.object(forKey: Key.keepDraftHistoryEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.keepDraftHistoryEnabled) }
    }

    func polishStrategy(for mode: TextPolishMode) -> TextPolishStrategy {
        guard let data = defaults.data(forKey: Key.polishStrategy(mode)),
              let decoded = try? JSONDecoder().decode(TextPolishStrategy.self, from: data) else {
            return .default(for: mode)
        }
        return decoded.normalized(for: mode)
    }

    func savePolishStrategy(_ strategy: TextPolishStrategy, for mode: TextPolishMode) {
        let normalized = strategy.normalized(for: mode)
        guard let data = try? JSONEncoder().encode(normalized) else { return }
        defaults.set(data, forKey: Key.polishStrategy(mode))
    }

    func resetPolishStrategy(for mode: TextPolishMode) {
        defaults.removeObject(forKey: Key.polishStrategy(mode))
    }

    func resetAllPolishStrategies() {
        for mode in TextPolishMode.allCases {
            resetPolishStrategy(for: mode)
        }
    }
}
