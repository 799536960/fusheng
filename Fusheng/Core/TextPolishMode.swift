import Foundation

enum TextPolishMode: String, CaseIterable, Identifiable, Codable {
    case original
    case clean
    case professional
    case concise

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .original: return "原文"
        case .clean: return "整理"
        case .professional: return "专业"
        case .concise: return "简短"
        }
    }
}
