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
