import XCTest
@testable import Fusheng

final class TextPolishStrategyTests: XCTestCase {
    func testDefaultStrategiesCarryTheirModeAndInstruction() {
        let original = TextPolishStrategy.default(for: .original)
        let clean = TextPolishStrategy.default(for: .clean)
        let professional = TextPolishStrategy.default(for: .professional)
        let concise = TextPolishStrategy.default(for: .concise)

        XCTAssertEqual(original.mode, .original)
        XCTAssertEqual(clean.mode, .clean)
        XCTAssertEqual(professional.mode, .professional)
        XCTAssertEqual(concise.mode, .concise)

        XCTAssertFalse(original.isCustomEnabled)
        XCTAssertFalse(clean.isCustomEnabled)
        XCTAssertFalse(professional.isCustomEnabled)
        XCTAssertFalse(concise.isCustomEnabled)

        XCTAssertTrue(original.modeInstruction.contains("只补齐必要标点"))
        XCTAssertTrue(clean.modeInstruction.contains("只做转写校对"))
        XCTAssertTrue(professional.modeInstruction.contains("断句整理得更清楚"))
        XCTAssertTrue(concise.modeInstruction.contains("不为了变短而省略"))
    }

    func testDefaultOptionsMatchModeIntent() {
        let original = TextPolishStrategy.default(for: .original)
        XCTAssertFalse(original.removeFillerWords)
        XCTAssertFalse(original.removeMeaninglessRepetition)
        XCTAssertFalse(original.fixObviousTypos)
        XCTAssertTrue(original.addNaturalPunctuation)
        XCTAssertFalse(original.allowLightPolish)
        XCTAssertEqual(original.conservatism, .strict)

        let clean = TextPolishStrategy.default(for: .clean)
        XCTAssertTrue(clean.removeFillerWords)
        XCTAssertTrue(clean.removeMeaninglessRepetition)
        XCTAssertTrue(clean.fixObviousTypos)
        XCTAssertTrue(clean.addNaturalPunctuation)
        XCTAssertFalse(clean.allowLightPolish)
        XCTAssertEqual(clean.conservatism, .balanced)

        let professional = TextPolishStrategy.default(for: .professional)
        XCTAssertTrue(professional.allowLightPolish)
        XCTAssertEqual(professional.conservatism, .balanced)

        let concise = TextPolishStrategy.default(for: .concise)
        XCTAssertTrue(concise.removeFillerWords)
        XCTAssertTrue(concise.removeMeaninglessRepetition)
        XCTAssertFalse(concise.allowLightPolish)
        XCTAssertEqual(concise.conservatism, .strict)
    }

    func testOptionInstructionsReflectSwitchesAndConservatism() {
        var strategy = TextPolishStrategy.default(for: .clean)
        strategy.removeFillerWords = true
        strategy.removeMeaninglessRepetition = false
        strategy.fixObviousTypos = true
        strategy.addNaturalPunctuation = false
        strategy.allowLightPolish = true
        strategy.conservatism = .natural

        let instruction = strategy.optionInstruction

        XCTAssertTrue(instruction.contains("删除明显口头禅"))
        XCTAssertTrue(instruction.contains("保留有实际表达作用的重复"))
        XCTAssertTrue(instruction.contains("修正明确错别字"))
        XCTAssertTrue(instruction.contains("不主动补充标点"))
        XCTAssertTrue(instruction.contains("允许轻微润色"))
        XCTAssertTrue(instruction.contains("表达更自然"))
    }

    func testStrategyCanBeNormalizedForSelectedMode() {
        var strategy = TextPolishStrategy.default(for: .clean)
        strategy.isCustomEnabled = true
        strategy.modeInstruction = "自定义策略"

        let normalized = strategy.normalized(for: .professional)

        XCTAssertEqual(normalized.mode, .professional)
        XCTAssertTrue(normalized.isCustomEnabled)
        XCTAssertEqual(normalized.modeInstruction, "自定义策略")
    }
}
