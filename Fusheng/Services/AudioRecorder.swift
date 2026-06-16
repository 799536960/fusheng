import AVFoundation
import Foundation

final class AudioRecorder: AudioRecording {
    private let engine = AVAudioEngine()
    private var continuation: AsyncThrowingStream<Data, Error>.Continuation?

    func startRecording() throws -> AsyncThrowingStream<Data, Error> {
        if engine.isRunning {
            stopRecording()
        }

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
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
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
}
