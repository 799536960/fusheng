import AVFoundation
import Foundation

enum AudioLevelNormalizer {
    static func normalizedLevel(rms: Double) -> Double {
        guard rms.isFinite, rms > 0 else { return 0 }

        let clampedRMS = min(max(rms, 0.000_01), 1)
        let decibels = 20 * log10(clampedRMS)
        let floorDecibels = -55.0
        let ceilingDecibels = -8.0
        let linearLevel = (decibels - floorDecibels) / (ceilingDecibels - floorDecibels)
        let clampedLevel = min(1, max(0, linearLevel))
        return min(0.96, pow(clampedLevel, 1.35) * 0.96)
    }
}

final class AudioRecorder: AudioRecording {
    private var engine: AVAudioEngine?
    private var continuation: AsyncThrowingStream<Data, Error>.Continuation?

    func startRecording() throws -> AsyncThrowingStream<Data, Error> {
        if engine?.isRunning == true {
            stopRecording()
        }

        let engine = AVAudioEngine()
        self.engine = engine
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 1,
            interleaved: true
        ) else {
            throw AppError.recorderFailed("无法创建 16 kHz PCM 格式")
        }
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw AppError.recorderFailed("无法创建音频格式转换器")
        }

        let stream = AsyncThrowingStream<Data, Error> { continuation in
            self.continuation = continuation
        }

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            do {
                let converted = try self.convert(buffer: buffer, converter: converter, outputFormat: outputFormat)
                self.continuation?.yield(converted)
                self.publishAudioLevel(from: converted)
            } catch {
                self.continuation?.finish(throwing: error)
                self.continuation = nil
            }
        }

        engine.prepare()
        try engine.start()
        return stream
    }

    func stopRecording() {
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            engine.reset()
        }
        engine = nil
        continuation?.finish()
        continuation = nil
    }

    private func convert(buffer: AVAudioPCMBuffer, converter: AVAudioConverter, outputFormat: AVAudioFormat) throws -> Data {
        let scaledFrameCapacity = Double(buffer.frameLength) * outputFormat.sampleRate / buffer.format.sampleRate
        let frameCapacity = max(1, AVAudioFrameCount(scaledFrameCapacity.rounded(.up)))
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: frameCapacity) else {
            throw AppError.recorderFailed("无法创建输出音频缓冲")
        }

        var error: NSError?
        var didProvideInput = false
        let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if didProvideInput {
                outStatus.pointee = .noDataNow
                return nil
            }

            didProvideInput = true
            outStatus.pointee = .haveData
            return buffer
        }

        if let error {
            throw AppError.recorderFailed(error.localizedDescription)
        }
        guard status != .error else {
            throw AppError.recorderFailed("音频转换失败")
        }
        guard let channelData = outputBuffer.int16ChannelData else {
            throw AppError.recorderFailed("PCM 数据为空")
        }

        let frameLength = Int(outputBuffer.frameLength)
        return Data(bytes: channelData[0], count: frameLength * MemoryLayout<Int16>.size)
    }

    private func publishAudioLevel(from data: Data) {
        let sampleCount = data.count / MemoryLayout<Int16>.size
        guard sampleCount > 0 else { return }

        let sumSquares = data.withUnsafeBytes { rawBuffer -> Double in
            guard let samples = rawBuffer.bindMemory(to: Int16.self).baseAddress else {
                return 0
            }

            var total = 0.0
            for index in 0..<sampleCount {
                let normalized = Double(samples[index]) / Double(Int16.max)
                total += normalized * normalized
            }
            return total
        }

        let rms = sqrt(sumSquares / Double(sampleCount))
        let level = AudioLevelNormalizer.normalizedLevel(rms: rms)
        Task { @MainActor in
            NotificationCenter.default.post(name: .audioLevelDidChange, object: nil, userInfo: ["level": level])
        }
    }
}
