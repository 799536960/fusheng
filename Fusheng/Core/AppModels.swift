import Foundation

extension Notification.Name {
    static let audioLevelDidChange = Notification.Name("FushengAudioLevelDidChange")
    static let draftHistoryDidChange = Notification.Name("FushengDraftHistoryDidChange")
    static let speechHotkeyDidChange = Notification.Name("FushengSpeechHotkeyDidChange")
    static let hotkeyRecorderCaptureDidChange = Notification.Name("FushengHotkeyRecorderCaptureDidChange")
    static let failedRecordingQueueDidChange = Notification.Name("FushengFailedRecordingQueueDidChange")
}

enum DiagnosticLog {
    private static let queue = DispatchQueue(label: "com.fusheng.voiceinput.diagnostics")
    private static let maxLogFileBytes: UInt64 = 1_000_000

    static var logFileURL: URL {
        FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appending(path: "Logs/Fusheng", directoryHint: .isDirectory)
            .appending(path: "hotkey-diagnostics.log")
    }

    static func write(category: String, message: String) {
        guard !isRunningTests else { return }

        queue.async {
            writeSynchronously(category: category, message: message)
        }
    }

    private static var isRunningTests: Bool {
        NSClassFromString("XCTestCase") != nil
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.arguments.contains { argument in
                argument == "-XCTest"
                    || argument.contains("XCTest")
                    || argument.hasSuffix(".xctest")
            }
            || Bundle.allBundles.contains { bundle in
                bundle.bundlePath.hasSuffix(".xctest")
            }
    }

    private static func writeSynchronously(category: String, message: String) {
        do {
            let fileManager = FileManager.default
            let url = logFileURL
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try rotateLogIfNeeded(fileManager: fileManager, url: url)

            if !fileManager.fileExists(atPath: url.path) {
                fileManager.createFile(atPath: url.path, contents: nil)
            }

            let sanitizedMessage = message
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let line = "\(timestamp) [\(category)] \(sanitizedMessage)\n"
            guard let data = line.data(using: .utf8) else { return }

            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            // Diagnostics must never affect the voice input workflow.
        }
    }

    private static func rotateLogIfNeeded(fileManager: FileManager, url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }

        guard let fileSize = try fileManager.attributesOfItem(atPath: url.path)[.size] as? UInt64,
              fileSize >= maxLogFileBytes else {
            return
        }

        let rotatedURL = url.deletingPathExtension().appendingPathExtension("log.1")
        if fileManager.fileExists(atPath: rotatedURL.path) {
            try fileManager.removeItem(at: rotatedURL)
        }
        try fileManager.moveItem(at: url, to: rotatedURL)
    }
}

enum DeliveryResult: Equatable {
    case pasted
    case savedDraft
}

enum DraftDeliveryStatus: Equatable {
    case pasted
    case savedDraft
    case pasteFailed
    case autoPasteDisabled
    case noInput(appName: String)
    case accessibilityPermissionMissing(appName: String)

    var displayText: String {
        switch self {
        case .pasted:
            return "已粘贴"
        case .savedDraft:
            return "已保存草稿"
        case .pasteFailed:
            return "粘贴失败"
        case .autoPasteDisabled:
            return "自动粘贴已关闭"
        case .noInput(let appName):
            return "\(appName) 无可输入位置"
        case .accessibilityPermissionMissing(let appName):
            return "\(appName) 缺少辅助功能权限"
        }
    }
}

struct RecognitionResult: Equatable {
    let rawText: String
    let partialText: String
}

struct PolishedText: Equatable {
    let rawText: String
    let polishedText: String
    let mode: TextPolishMode
}

struct DraftSnapshot: Identifiable, Equatable {
    let id: UUID
    let polishedText: String
    let rawASRText: String
    let createdAt: Date
    let sourceAppName: String
    let mode: TextPolishMode
    let deliveryStatus: DraftDeliveryStatus
    let errorSummary: String?
}
