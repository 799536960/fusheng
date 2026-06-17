import XCTest
@testable import Fusheng

final class FailedRecordingAudioStoreTests: XCTestCase {
    func testWriterAppendsReadsAndDeletesPCMFile() async throws {
        let baseURL = FileManager.default.temporaryDirectory
            .appending(path: "FushengAudioStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let store = FailedRecordingAudioStore(baseDirectory: baseURL)
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let writer = try store.makeWriter(id: id)

        try writer.append(Data([1, 2, 3]))
        try writer.append(Data([4, 5]))
        try writer.close()

        XCTAssertTrue(store.fileExists(at: writer.filePath))

        var chunks: [Data] = []
        for try await chunk in try store.audioChunks(from: writer.filePath) {
            chunks.append(chunk)
        }
        XCTAssertEqual(chunks.reduce(Data(), +), Data([1, 2, 3, 4, 5]))

        store.deleteAudio(at: writer.filePath)

        XCTAssertFalse(store.fileExists(at: writer.filePath))
    }

    func testDeletingMissingAudioDoesNotThrow() throws {
        let baseURL = FileManager.default.temporaryDirectory
            .appending(path: "FushengAudioStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let store = FailedRecordingAudioStore(baseDirectory: baseURL)

        store.deleteAudio(at: baseURL.appending(path: "missing.pcm").path)
    }
}
