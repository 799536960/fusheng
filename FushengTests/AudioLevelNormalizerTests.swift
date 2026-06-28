import XCTest
@testable import Fusheng

final class AudioLevelNormalizerTests: XCTestCase {
    func testNormalizerKeepsSilenceAtFloor() {
        XCTAssertEqual(AudioLevelNormalizer.normalizedLevel(rms: 0), 0, accuracy: 0.0001)
        XCTAssertEqual(AudioLevelNormalizer.normalizedLevel(rms: -1), 0, accuracy: 0.0001)
        XCTAssertEqual(AudioLevelNormalizer.normalizedLevel(rms: .nan), 0, accuracy: 0.0001)
    }

    func testNormalizerDoesNotSaturateNormalSpeechLevels() {
        let quietSpeech = AudioLevelNormalizer.normalizedLevel(rms: 0.02)
        let normalSpeech = AudioLevelNormalizer.normalizedLevel(rms: 0.05)
        let strongSpeech = AudioLevelNormalizer.normalizedLevel(rms: 0.15)

        XCTAssertGreaterThan(quietSpeech, 0.10)
        XCTAssertGreaterThan(normalSpeech, quietSpeech)
        XCTAssertGreaterThan(strongSpeech, normalSpeech)
        XCTAssertLessThan(normalSpeech, 0.70)
        XCTAssertLessThan(strongSpeech, 0.92)
    }

    func testNormalizerIsMonotonicAndClamped() {
        let levels = [0.001, 0.005, 0.02, 0.05, 0.15, 0.4, 1.0]
            .map(AudioLevelNormalizer.normalizedLevel)

        XCTAssertEqual(levels, levels.sorted())
        XCTAssertGreaterThanOrEqual(levels.first ?? -1, 0)
        XCTAssertLessThanOrEqual(levels.last ?? 2, 0.96)
    }
}
