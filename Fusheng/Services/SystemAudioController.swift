import Darwin
import Foundation
import OSLog

private let systemAudioLogger = Logger(subsystem: "com.fusheng.voiceinput", category: "SystemAudio")
private let mediaRemoteQueryTimeout: TimeInterval = 0.8

@MainActor
final class SystemAudioController: SystemAudioControlling {
    private let mediaRemote: MediaRemotePlaybackControlling

    init() {
        self.mediaRemote = MediaRemoteClient()
    }

    init(mediaRemote: MediaRemotePlaybackControlling) {
        self.mediaRemote = mediaRemote
    }

    func pauseForRecording() async -> Bool {
        let playbackState = await mediaRemote.currentPlaybackState()
        let isPlaying = playbackState == .playing ? nil : await mediaRemote.currentNowPlayingApplicationIsPlaying()
        let playbackRate = playbackState == .playing || isPlaying == true ? nil : await mediaRemote.currentPlaybackRate()
        let wasPlaying = playbackState == .playing || isPlaying == true || playbackRate.indicatesPlayback
        DiagnosticLog.write(
            category: "SystemAudio",
            message: "pause requested playbackState=\(playbackState.logName) isPlaying=\(isPlaying.logName) playbackRate=\(playbackRate.logName)"
        )

        let didPause = mediaRemote.send(command: .pause)
        systemAudioLogger.info("system audio pause command sent result=\(didPause, privacy: .public)")
        DiagnosticLog.write(
            category: "SystemAudio",
            message: "pause command sent result=\(didPause) playbackState=\(playbackState.logName) isPlaying=\(isPlaying.logName) playbackRate=\(playbackRate.logName)"
        )
        return wasPlaying && didPause
    }

    func resumeAfterRecording() async {
        let didResume = mediaRemote.send(command: .play)
        systemAudioLogger.info("system audio resume command sent result=\(didResume, privacy: .public)")
        DiagnosticLog.write(category: "SystemAudio", message: "resume command sent result=\(didResume)")
    }
}

enum MediaRemoteCommand: Int32 {
    case play = 0
    case pause = 1
}

enum MediaRemotePlaybackState: Int32 {
    case unknown = 0
    case playing = 1
    case paused = 2
    case stopped = 3
    case interrupted = 4
}

private extension Optional where Wrapped == MediaRemotePlaybackState {
    var logName: String {
        switch self {
        case .some(.unknown):
            return "unknown"
        case .some(.playing):
            return "playing"
        case .some(.paused):
            return "paused"
        case .some(.stopped):
            return "stopped"
        case .some(.interrupted):
            return "interrupted"
        case .none:
            return "unavailable"
        }
    }
}

private extension Optional where Wrapped == Double {
    var logName: String {
        guard let value = self else { return "unavailable" }
        return String(format: "%.3f", value)
    }

    var indicatesPlayback: Bool {
        guard let value = self else { return false }
        return value > 0.01
    }
}

private extension Optional where Wrapped == Bool {
    var logName: String {
        guard let value = self else { return "unavailable" }
        return String(value)
    }
}

@MainActor
protocol MediaRemotePlaybackControlling {
    func currentPlaybackState() async -> MediaRemotePlaybackState?
    func currentNowPlayingApplicationIsPlaying() async -> Bool?
    func currentPlaybackRate() async -> Double?
    func send(command: MediaRemoteCommand) -> Bool
}

@MainActor
private final class MediaRemoteClient: MediaRemotePlaybackControlling {
    private typealias PlaybackStateCallback = @convention(block) (Int32) -> Void
    private typealias GetPlaybackStateFunction = @convention(c) (DispatchQueue, @escaping PlaybackStateCallback) -> Void
    private typealias NowPlayingIsPlayingCallback = @convention(block) (UInt8) -> Void
    private typealias GetNowPlayingApplicationIsPlayingFunction = @convention(c) (DispatchQueue, @escaping NowPlayingIsPlayingCallback) -> Void
    private typealias NowPlayingInfoCallback = @convention(block) (CFDictionary?) -> Void
    private typealias GetNowPlayingInfoFunction = @convention(c) (DispatchQueue, @escaping NowPlayingInfoCallback) -> Void
    private typealias SendCommandFunction = @convention(c) (Int32, CFDictionary?) -> Void

    private let frameworkHandle: UnsafeMutableRawPointer?
    private let getPlaybackState: GetPlaybackStateFunction?
    private let getNowPlayingApplicationIsPlaying: GetNowPlayingApplicationIsPlayingFunction?
    private let getNowPlayingInfo: GetNowPlayingInfoFunction?
    private let sendCommand: SendCommandFunction?

    init() {
        frameworkHandle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW)

        if let frameworkHandle,
           let symbol = dlsym(frameworkHandle, "MRMediaRemoteGetNowPlayingApplicationPlaybackState") {
            getPlaybackState = unsafeBitCast(symbol, to: GetPlaybackStateFunction.self)
        } else {
            getPlaybackState = nil
        }

        if let frameworkHandle,
           let symbol = dlsym(frameworkHandle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying") {
            getNowPlayingApplicationIsPlaying = unsafeBitCast(symbol, to: GetNowPlayingApplicationIsPlayingFunction.self)
        } else {
            getNowPlayingApplicationIsPlaying = nil
        }

        if let frameworkHandle,
           let symbol = dlsym(frameworkHandle, "MRMediaRemoteGetNowPlayingInfo") {
            getNowPlayingInfo = unsafeBitCast(symbol, to: GetNowPlayingInfoFunction.self)
        } else {
            getNowPlayingInfo = nil
        }

        if let frameworkHandle,
           let symbol = dlsym(frameworkHandle, "MRMediaRemoteSendCommand") {
            sendCommand = unsafeBitCast(symbol, to: SendCommandFunction.self)
        } else {
            sendCommand = nil
        }
    }

    deinit {
        if let frameworkHandle {
            dlclose(frameworkHandle)
        }
    }

    func currentPlaybackState() async -> MediaRemotePlaybackState? {
        guard let getPlaybackState else {
            systemAudioLogger.info("MediaRemote playback state function unavailable")
            return nil
        }

        return await withCheckedContinuation { continuation in
            let box = PlaybackStateContinuationBox(continuation: continuation)

            getPlaybackState(.main) { rawState in
                box.resume(with: MediaRemotePlaybackState(rawValue: rawState))
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + mediaRemoteQueryTimeout) {
                box.resume(with: nil)
            }
        }
    }

    func currentNowPlayingApplicationIsPlaying() async -> Bool? {
        guard let getNowPlayingApplicationIsPlaying else {
            systemAudioLogger.info("MediaRemote now playing isPlaying function unavailable")
            DiagnosticLog.write(category: "SystemAudio", message: "now playing isPlaying function unavailable")
            return nil
        }

        return await withCheckedContinuation { continuation in
            let box = BoolContinuationBox(continuation: continuation)

            getNowPlayingApplicationIsPlaying(.main) { rawValue in
                box.resume(with: rawValue != 0)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + mediaRemoteQueryTimeout) {
                box.resume(with: nil)
            }
        }
    }

    func currentPlaybackRate() async -> Double? {
        guard let getNowPlayingInfo else {
            systemAudioLogger.info("MediaRemote now playing info function unavailable")
            DiagnosticLog.write(category: "SystemAudio", message: "now playing info function unavailable")
            return nil
        }

        return await withCheckedContinuation { continuation in
            let box = PlaybackRateContinuationBox(continuation: continuation)

            getNowPlayingInfo(.main) { info in
                let dictionary = info as NSDictionary?
                let value = dictionary?["kMRMediaRemoteNowPlayingInfoPlaybackRate"]
                if let number = value as? NSNumber {
                    box.resume(with: number.doubleValue)
                } else if let double = value as? Double {
                    box.resume(with: double)
                } else {
                    box.resume(with: nil)
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + mediaRemoteQueryTimeout) {
                box.resume(with: nil)
            }
        }
    }

    func send(command: MediaRemoteCommand) -> Bool {
        guard let sendCommand else {
            systemAudioLogger.info("MediaRemote send command function unavailable")
            return false
        }

        sendCommand(command.rawValue, nil)
        return true
    }
}

private final class BoolContinuationBox {
    private let lock = NSLock()
    private var didResume = false
    private let continuation: CheckedContinuation<Bool?, Never>

    init(continuation: CheckedContinuation<Bool?, Never>) {
        self.continuation = continuation
    }

    func resume(with value: Bool?) {
        lock.lock()
        defer { lock.unlock() }

        guard !didResume else { return }
        didResume = true
        continuation.resume(returning: value)
    }
}

private final class PlaybackRateContinuationBox {
    private let lock = NSLock()
    private var didResume = false
    private let continuation: CheckedContinuation<Double?, Never>

    init(continuation: CheckedContinuation<Double?, Never>) {
        self.continuation = continuation
    }

    func resume(with rate: Double?) {
        lock.lock()
        defer { lock.unlock() }

        guard !didResume else { return }
        didResume = true
        continuation.resume(returning: rate)
    }
}

private final class PlaybackStateContinuationBox {
    private let lock = NSLock()
    private var didResume = false
    private let continuation: CheckedContinuation<MediaRemotePlaybackState?, Never>

    init(continuation: CheckedContinuation<MediaRemotePlaybackState?, Never>) {
        self.continuation = continuation
    }

    func resume(with state: MediaRemotePlaybackState?) {
        lock.lock()
        defer { lock.unlock() }

        guard !didResume else { return }
        didResume = true
        continuation.resume(returning: state)
    }
}
