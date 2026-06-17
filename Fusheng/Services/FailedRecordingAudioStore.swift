import Foundation

final class FailedRecordingAudioStore: FailedRecordingAudioStoring {
    private let baseDirectory: URL
    private let fileManager: FileManager

    init(
        baseDirectory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Fusheng", directoryHint: .isDirectory)
            .appending(path: "FailedRecordings", directoryHint: .isDirectory),
        fileManager: FileManager = .default
    ) {
        self.baseDirectory = baseDirectory
        self.fileManager = fileManager
    }

    func makeWriter(id: UUID) throws -> FailedRecordingAudioWriting {
        try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        let url = baseDirectory.appending(path: "\(id.uuidString).pcm")
        fileManager.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        return FailedRecordingAudioWriter(fileURL: url, handle: handle, fileManager: fileManager)
    }

    func fileExists(at path: String) -> Bool {
        fileManager.fileExists(atPath: path)
    }

    func audioChunks(from path: String) throws -> AsyncThrowingStream<Data, Error> {
        guard fileManager.fileExists(atPath: path) else {
            throw AppError.recorderFailed("音频文件缺失")
        }

        return AsyncThrowingStream { continuation in
            Task.detached {
                do {
                    let data = try Data(contentsOf: URL(filePath: path))
                    let chunkSize = 4096
                    var offset = 0
                    while offset < data.count {
                        let end = min(offset + chunkSize, data.count)
                        continuation.yield(data.subdata(in: offset..<end))
                        offset = end
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func deleteAudio(at path: String) {
        try? fileManager.removeItem(atPath: path)
    }
}

private final class FailedRecordingAudioWriter: FailedRecordingAudioWriting {
    let filePath: String
    private let fileURL: URL
    private let handle: FileHandle
    private let fileManager: FileManager
    private var isClosed = false

    init(fileURL: URL, handle: FileHandle, fileManager: FileManager) {
        self.fileURL = fileURL
        self.filePath = fileURL.path
        self.handle = handle
        self.fileManager = fileManager
    }

    func append(_ data: Data) throws {
        guard !isClosed else { return }
        try handle.write(contentsOf: data)
    }

    func close() throws {
        guard !isClosed else { return }
        try handle.close()
        isClosed = true
    }

    func delete() {
        try? close()
        try? fileManager.removeItem(at: fileURL)
    }
}
