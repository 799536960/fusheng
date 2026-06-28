import AudioToolbox
import CoreAudio
import Foundation
import OSLog

private let systemAudioLogger = Logger(subsystem: "com.fusheng.voiceinput", category: "SystemAudio")

struct SystemAudioOutputState: Equatable {
    let isMuted: Bool?
    let volume: Float32?
}

@MainActor
protocol SystemAudioOutputControlling {
    func captureState() -> SystemAudioOutputState?
    func setMuted(_ isMuted: Bool) -> Bool
    func setVolume(_ volume: Float32) -> Bool
    func restore(_ state: SystemAudioOutputState) -> Bool
}

@MainActor
final class SystemAudioController: SystemAudioControlling {
    private let outputController: SystemAudioOutputControlling
    private var stateBeforeRecording: SystemAudioOutputState?

    init() {
        self.outputController = CoreAudioSystemOutputController()
    }

    init(outputController: SystemAudioOutputControlling) {
        self.outputController = outputController
    }

    func silenceForRecording() async -> Bool {
        guard let state = outputController.captureState() else {
            DiagnosticLog.write(category: "SystemAudio", message: "silence skipped because output state was unavailable")
            return false
        }

        stateBeforeRecording = state
        let didMute = outputController.setMuted(true)
        let didSetFallbackVolume = didMute ? false : outputController.setVolume(0)
        let didSilence = didMute || didSetFallbackVolume

        DiagnosticLog.write(
            category: "SystemAudio",
            message: "silence requested didMute=\(didMute) didSetFallbackVolume=\(didSetFallbackVolume) previousMuted=\(state.isMuted.logName) previousVolume=\(state.volume.logName)"
        )

        if !didSilence {
            stateBeforeRecording = nil
        }

        return didSilence
    }

    func restoreAfterRecording() async {
        guard let state = stateBeforeRecording else {
            DiagnosticLog.write(category: "SystemAudio", message: "restore skipped because no output state was captured")
            return
        }

        stateBeforeRecording = nil
        let didRestore = outputController.restore(state)
        DiagnosticLog.write(
            category: "SystemAudio",
            message: "restore requested result=\(didRestore) muted=\(state.isMuted.logName) volume=\(state.volume.logName)"
        )
    }
}

private final class CoreAudioSystemOutputController: SystemAudioOutputControlling {
    func captureState() -> SystemAudioOutputState? {
        guard let deviceID = defaultOutputDeviceID() else {
            systemAudioLogger.info("default output device unavailable")
            return nil
        }

        let isMuted = readBoolProperty(
            selector: kAudioDevicePropertyMute,
            scope: kAudioDevicePropertyScopeOutput,
            deviceID: deviceID
        )
        let volume = readFloat32Property(
            selector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            scope: kAudioDevicePropertyScopeOutput,
            deviceID: deviceID
        )

        guard isMuted != nil || volume != nil else {
            systemAudioLogger.info("default output device exposes neither mute nor main volume")
            return nil
        }

        return SystemAudioOutputState(isMuted: isMuted, volume: volume)
    }

    func setMuted(_ isMuted: Bool) -> Bool {
        guard let deviceID = defaultOutputDeviceID() else { return false }
        return writeBoolProperty(
            selector: kAudioDevicePropertyMute,
            scope: kAudioDevicePropertyScopeOutput,
            deviceID: deviceID,
            value: isMuted
        )
    }

    func setVolume(_ volume: Float32) -> Bool {
        guard let deviceID = defaultOutputDeviceID() else { return false }
        return writeFloat32Property(
            selector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            scope: kAudioDevicePropertyScopeOutput,
            deviceID: deviceID,
            value: min(max(volume, 0), 1)
        )
    }

    func restore(_ state: SystemAudioOutputState) -> Bool {
        var didRestore = false

        if let volume = state.volume {
            didRestore = setVolume(volume) || didRestore
        }

        if let isMuted = state.isMuted {
            didRestore = setMuted(isMuted) || didRestore
        }

        return didRestore
    }

    private func defaultOutputDeviceID() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceID
        )

        guard status == noErr, deviceID != AudioObjectID(kAudioObjectUnknown) else {
            systemAudioLogger.info("failed reading default output device status=\(status)")
            return nil
        }

        return deviceID
    }

    private func readBoolProperty(
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        deviceID: AudioObjectID
    ) -> Bool? {
        var address = audioPropertyAddress(selector: selector, scope: scope)
        guard AudioObjectHasProperty(deviceID, &address) else { return nil }

        var value: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &value)
        guard status == noErr else {
            systemAudioLogger.info("failed reading bool property selector=\(selector) status=\(status)")
            return nil
        }

        return value != 0
    }

    private func writeBoolProperty(
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        deviceID: AudioObjectID,
        value: Bool
    ) -> Bool {
        var address = audioPropertyAddress(selector: selector, scope: scope)
        guard isPropertySettable(deviceID: deviceID, address: &address) else { return false }

        var rawValue: UInt32 = value ? 1 : 0
        let dataSize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, dataSize, &rawValue)
        if status != noErr {
            systemAudioLogger.info("failed writing bool property selector=\(selector) status=\(status)")
        }
        return status == noErr
    }

    private func readFloat32Property(
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        deviceID: AudioObjectID
    ) -> Float32? {
        var address = audioPropertyAddress(selector: selector, scope: scope)
        guard AudioObjectHasProperty(deviceID, &address) else { return nil }

        var value: Float32 = 0
        var dataSize = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &value)
        guard status == noErr else {
            systemAudioLogger.info("failed reading Float32 property selector=\(selector) status=\(status)")
            return nil
        }

        return value
    }

    private func writeFloat32Property(
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        deviceID: AudioObjectID,
        value: Float32
    ) -> Bool {
        var address = audioPropertyAddress(selector: selector, scope: scope)
        guard isPropertySettable(deviceID: deviceID, address: &address) else { return false }

        var rawValue = value
        let dataSize = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, dataSize, &rawValue)
        if status != noErr {
            systemAudioLogger.info("failed writing Float32 property selector=\(selector) status=\(status)")
        }
        return status == noErr
    }

    private func audioPropertyAddress(
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private func isPropertySettable(
        deviceID: AudioObjectID,
        address: inout AudioObjectPropertyAddress
    ) -> Bool {
        let selector = address.mSelector
        guard AudioObjectHasProperty(deviceID, &address) else { return false }

        var isSettable = DarwinBoolean(false)
        let status = AudioObjectIsPropertySettable(deviceID, &address, &isSettable)
        guard status == noErr else {
            systemAudioLogger.info("failed checking property settable selector=\(selector) status=\(status)")
            return false
        }

        return isSettable.boolValue
    }
}

private extension Optional where Wrapped == Bool {
    var logName: String {
        guard let value = self else { return "unavailable" }
        return String(value)
    }
}

private extension Optional where Wrapped == Float32 {
    var logName: String {
        guard let value = self else { return "unavailable" }
        return String(format: "%.3f", value)
    }
}
