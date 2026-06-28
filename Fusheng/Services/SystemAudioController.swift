import Darwin
import Foundation
import OSLog

private let systemAudioLogger = Logger(subsystem: "com.fusheng.voiceinput", category: "SystemAudio")

@MainActor
final class SystemAudioController: SystemAudioControlling {
    private let mediaRemote: MediaRemotePlaybackControlling

    init() {
        self.mediaRemote = MediaRemoteClient()
    }

    private init(mediaRemote: MediaRemotePlaybackControlling) {
        self.mediaRemote = mediaRemote
    }

    func pauseForRecording() async -> Bool {
        guard await mediaRemote.currentPlaybackState() == .playing else {
            systemAudioLogger.info("system audio pause skipped because no active playback was detected")
            return false
        }

        let didPause = mediaRemote.send(command: .pause)
        systemAudioLogger.info("system audio pause command sent result=\(didPause, privacy: .public)")
        return didPause
    }

    func resumeAfterRecording() async {
        let didResume = mediaRemote.send(command: .play)
        systemAudioLogger.info("system audio resume command sent result=\(didResume, privacy: .public)")
    }
}

private enum MediaRemoteCommand: Int32 {
    case play = 0
    case pause = 1
}

private enum MediaRemotePlaybackState: Int32 {
    case unknown = 0
    case playing = 1
    case paused = 2
    case stopped = 3
    case interrupted = 4
}

@MainActor
private protocol MediaRemotePlaybackControlling {
    func currentPlaybackState() async -> MediaRemotePlaybackState?
    func send(command: MediaRemoteCommand) -> Bool
}

@MainActor
private final class MediaRemoteClient: MediaRemotePlaybackControlling {
    private typealias PlaybackStateCallback = @convention(block) (Int32) -> Void
    private typealias GetPlaybackStateFunction = @convention(c) (DispatchQueue, @escaping PlaybackStateCallback) -> Void
    private typealias SendCommandFunction = @convention(c) (Int32, CFDictionary?) -> Void

    private let frameworkHandle: UnsafeMutableRawPointer?
    private let getPlaybackState: GetPlaybackStateFunction?
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

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
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
