import XCTest
@testable import Fusheng

final class AudioStreamTeeTests: XCTestCase {
    func testTeeWritesEveryChunkAndYieldsSameChunks() async throws {
        let writer = MemoryAudioWriter(filePath: "/tmp/audio.pcm")
        let input = AsyncThrowingStream<Data, Error> { continuation in
            continuation.yield(Data([1]))
            continuation.yield(Data([2, 3]))
            continuation.finish()
        }

        let output = AudioStreamTee.tee(input, writer: writer)

        var received: [Data] = []
        for try await chunk in output {
            received.append(chunk)
        }

        XCTAssertEqual(received, [Data([1]), Data([2, 3])])
        XCTAssertEqual(writer.written, [Data([1]), Data([2, 3])])
        XCTAssertEqual(writer.closeCount, 1)
    }

    func testTeeClosesWriterWhenInputThrows() async {
        let writer = MemoryAudioWriter(filePath: "/tmp/audio.pcm")
        let input = AsyncThrowingStream<Data, Error> { continuation in
            continuation.finish(throwing: AppError.recorderFailed("boom"))
        }

        do {
            for try await _ in AudioStreamTee.tee(input, writer: writer) {}
            XCTFail("Expected throw")
        } catch {
            XCTAssertEqual(writer.closeCount, 1)
        }
    }
}

private final class MemoryAudioWriter: FailedRecordingAudioWriting {
    let filePath: String
    private(set) var written: [Data] = []
    private(set) var closeCount = 0

    init(filePath: String) {
        self.filePath = filePath
    }

    func append(_ data: Data) throws {
        written.append(data)
    }

    func close() throws {
        closeCount += 1
    }

    func delete() {}
}
