import Foundation

enum TextPolishConservatism: String, CaseIterable, Identifiable, Codable {
    case strict
    case balanced
    case natural

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .strict:
            return "严格保留"
        case .balanced:
            return "平衡整理"
        case .natural:
            return "更自然"
        }
    }

    var promptInstruction: String {
        switch self {
        case .strict:
            return "保守程度：严格保留。尽量不改句子，只做必要校对。"
        case .balanced:
            return "保守程度：平衡整理。删除明显噪音，保持原意和表达关系。"
        case .natural:
            return "保守程度：更自然。可以让表达更自然，但仍不得补充原文没有的信息。"
        }
    }
}

struct TextPolishStrategy: Equatable, Codable {
    var mode: TextPolishMode
    var isCustomEnabled: Bool
    var removeFillerWords: Bool
    var removeMeaninglessRepetition: Bool
    var fixObviousTypos: Bool
    var addNaturalPunctuation: Bool
    var allowLightPolish: Bool
    var conservatism: TextPolishConservatism
    var modeInstruction: String
    var extraInstructions: String

    static func `default`(for mode: TextPolishMode) -> TextPolishStrategy {
        switch mode {
        case .original:
            return TextPolishStrategy(
                mode: mode,
                isCustomEnabled: false,
                removeFillerWords: false,
                removeMeaninglessRepetition: false,
                fixObviousTypos: false,
                addNaturalPunctuation: true,
                allowLightPolish: false,
                conservatism: .strict,
                modeInstruction: "保留原意和口语表达，只补齐必要标点，不扩写，不删除内容。",
                extraInstructions: ""
            )
        case .clean:
            return TextPolishStrategy(
                mode: mode,
                isCustomEnabled: false,
                removeFillerWords: true,
                removeMeaninglessRepetition: true,
                fixObviousTypos: true,
                addNaturalPunctuation: true,
                allowLightPolish: false,
                conservatism: .balanced,
                modeInstruction: "只做转写校对：删除明显口头禅和无意义重复，修正明显错别字或明确的 ASR 同音错词，补充自然标点；不做摘要、不做润色、不重写句子。",
                extraInstructions: ""
            )
        case .professional:
            return TextPolishStrategy(
                mode: mode,
                isCustomEnabled: false,
                removeFillerWords: true,
                removeMeaninglessRepetition: true,
                fixObviousTypos: true,
                addNaturalPunctuation: true,
                allowLightPolish: true,
                conservatism: .balanced,
                modeInstruction: "在不改变原意的前提下，修正明显错字，删除明显口头禅，把断句整理得更清楚；不要添加正式套话，不要替用户补充没说出口的需求、原因或结论。",
                extraInstructions: ""
            )
        case .concise:
            return TextPolishStrategy(
                mode: mode,
                isCustomEnabled: false,
                removeFillerWords: true,
                removeMeaninglessRepetition: true,
                fixObviousTypos: true,
                addNaturalPunctuation: true,
                allowLightPolish: false,
                conservatism: .strict,
                modeInstruction: "只删除明显重复和无意义口头词；保留关键意思和原句行动关系，不为了变短而省略对象、条件、否定词或语气。",
                extraInstructions: ""
            )
        }
    }

    var optionInstruction: String {
        [
            removeFillerWords ? "删除明显口头禅。" : "保留有实际表达作用的口语词。",
            removeMeaninglessRepetition ? "删除无意义重复。" : "保留有实际表达作用的重复。",
            fixObviousTypos ? "修正明确错别字或 ASR 同音错词。" : "不猜测修正不确定的错词。",
            addNaturalPunctuation ? "补充自然标点。" : "不主动补充标点。",
            allowLightPolish ? "允许轻微润色，但不得改变原意。" : "不做润色，不重写句子。",
            conservatism.promptInstruction
        ].joined(separator: "")
    }

    var resolvedModeInstruction: String {
        let trimmed = modeInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return Self.default(for: mode).modeInstruction
        }
        return trimmed
    }

    var resolvedExtraInstructions: String {
        extraInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func normalized(for mode: TextPolishMode) -> TextPolishStrategy {
        var copy = self
        copy.mode = mode
        return copy
    }
}
