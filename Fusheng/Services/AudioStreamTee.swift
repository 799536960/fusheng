import Foundation

enum AudioStreamTee {
    static func tee(
        _ input: AsyncThrowingStream<Data, Error>,
        writer: FailedRecordingAudioWriting
    ) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await chunk in input {
                        try writer.append(chunk)
                        continuation.yield(chunk)
                    }
                    try writer.close()
                    continuation.finish()
                } catch {
                    try? writer.close()
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
