import Foundation
import KeyboardShortcuts

@MainActor
protocol HotkeyEventRegistering {
    func onKeyDown(_ action: @escaping () -> Void)
    func onKeyUp(_ action: @escaping () -> Void)
}

@MainActor
struct KeyboardShortcutsHotkeyRegisterer: HotkeyEventRegistering {
    func onKeyDown(_ action: @escaping () -> Void) {
        KeyboardShortcuts.onKeyDown(for: .voiceInput, action: action)
    }

    func onKeyUp(_ action: @escaping () -> Void) {
        KeyboardShortcuts.onKeyUp(for: .voiceInput, action: action)
    }
}

@MainActor
final class HotkeyService {
    private let settings: SettingsProviding
    private let registerer: HotkeyEventRegistering
    private let onToggle: () -> Void
    private let onStart: () -> Void
    private let onFinish: () -> Void

    init(
        settings: SettingsProviding,
        registerer: HotkeyEventRegistering,
        onToggle: @escaping () -> Void,
        onStart: @escaping () -> Void,
        onFinish: @escaping () -> Void
    ) {
        self.settings = settings
        self.registerer = registerer
        self.onToggle = onToggle
        self.onStart = onStart
        self.onFinish = onFinish
    }

    convenience init(
        settings: SettingsProviding,
        onToggle: @escaping () -> Void,
        onStart: @escaping () -> Void,
        onFinish: @escaping () -> Void
    ) {
        self.init(
            settings: settings,
            registerer: KeyboardShortcutsHotkeyRegisterer(),
            onToggle: onToggle,
            onStart: onStart,
            onFinish: onFinish
        )
    }

    func start() {
        registerer.onKeyDown { [weak self] in
            guard let self else { return }
            switch self.settings.triggerMode {
            case .toggle:
                self.onToggle()
            case .hold:
                self.onStart()
            }
        }

        registerer.onKeyUp { [weak self] in
            guard let self else { return }
            if self.settings.triggerMode == .hold {
                self.onFinish()
            }
        }
    }
}
