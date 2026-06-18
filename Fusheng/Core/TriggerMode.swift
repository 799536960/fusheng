import AppKit
import Foundation

enum TriggerMode: String, CaseIterable, Identifiable, Codable {
    case toggle
    case hold

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .toggle: return "按一次开始/再按一次结束"
        case .hold: return "按住说话/松开结束"
        }
    }
}

struct SpeechHotkey: Equatable, Codable {
    let keyCode: UInt16
    let displayName: String

    static let f1 = SpeechHotkey(keyCode: 122, displayName: "F1")
    static let f2 = SpeechHotkey(keyCode: 120, displayName: "F2")
    static let f3 = SpeechHotkey(keyCode: 99, displayName: "F3")
    static let f4 = SpeechHotkey(keyCode: 118, displayName: "F4")
    static let f5 = SpeechHotkey(keyCode: 96, displayName: "F5")
    static let f6 = SpeechHotkey(keyCode: 97, displayName: "F6")
    static let f7 = SpeechHotkey(keyCode: 98, displayName: "F7")
    static let f8 = SpeechHotkey(keyCode: 100, displayName: "F8")
    static let f9 = SpeechHotkey(keyCode: 101, displayName: "F9")
    static let f10 = SpeechHotkey(keyCode: 109, displayName: "F10")
    static let f11 = SpeechHotkey(keyCode: 103, displayName: "F11")
    static let f12 = SpeechHotkey(keyCode: 111, displayName: "F12")
    static let f13 = SpeechHotkey(keyCode: 105, displayName: "F13")
    static let f14 = SpeechHotkey(keyCode: 107, displayName: "F14")
    static let f15 = SpeechHotkey(keyCode: 113, displayName: "F15")
    static let f16 = SpeechHotkey(keyCode: 106, displayName: "F16")
    static let f17 = SpeechHotkey(keyCode: 64, displayName: "F17")
    static let f18 = SpeechHotkey(keyCode: 79, displayName: "F18")
    static let f19 = SpeechHotkey(keyCode: 80, displayName: "F19")

    static func from(event: NSEvent) -> SpeechHotkey {
        let keyCode = UInt16(event.keyCode)
        return SpeechHotkey(
            keyCode: keyCode,
            displayName: displayName(forKeyCode: keyCode, characters: event.charactersIgnoringModifiers)
        )
    }

    static func legacy(_ key: SpeechHotkeyKey) -> SpeechHotkey {
        SpeechHotkey(keyCode: key.keyCode, displayName: key.displayName)
    }

    static func displayName(forKeyCode keyCode: UInt16, characters: String?) -> String {
        if let name = keyCodeDisplayNames[keyCode] {
            return name
        }

        let trimmed = characters?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            return trimmed.uppercased()
        }

        return "Key \(keyCode)"
    }

    private static let keyCodeDisplayNames: [UInt16: String] = [
        36: "回车",
        48: "Tab",
        49: "空格",
        51: "Delete",
        53: "Esc",
        64: "F17",
        79: "F18",
        80: "F19",
        96: "F5",
        97: "F6",
        98: "F7",
        99: "F3",
        100: "F8",
        101: "F9",
        103: "F11",
        105: "F13",
        106: "F16",
        107: "F14",
        109: "F10",
        111: "F12",
        113: "F15",
        118: "F4",
        120: "F2",
        122: "F1",
        123: "←",
        124: "→",
        125: "↓",
        126: "↑"
    ]
}

enum SpeechHotkeyKey: String, CaseIterable, Identifiable, Codable {
    case f1 = "F1"
    case f2 = "F2"
    case f3 = "F3"
    case f4 = "F4"
    case f5 = "F5"
    case f6 = "F6"
    case f7 = "F7"
    case f8 = "F8"
    case f9 = "F9"
    case f10 = "F10"
    case f11 = "F11"
    case f12 = "F12"
    case f13 = "F13"
    case f14 = "F14"
    case f15 = "F15"
    case f16 = "F16"
    case f17 = "F17"
    case f18 = "F18"
    case f19 = "F19"

    var id: String { rawValue }
    var displayName: String { rawValue }

    var keyCode: UInt16 {
        switch self {
        case .f1: return 122
        case .f2: return 120
        case .f3: return 99
        case .f4: return 118
        case .f5: return 96
        case .f6: return 97
        case .f7: return 98
        case .f8: return 100
        case .f9: return 101
        case .f10: return 109
        case .f11: return 103
        case .f12: return 111
        case .f13: return 105
        case .f14: return 107
        case .f15: return 113
        case .f16: return 106
        case .f17: return 64
        case .f18: return 79
        case .f19: return 80
        }
    }
}
