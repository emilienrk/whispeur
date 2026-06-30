// AudioCaptureService.swift
// Whispeur
//
// Audio capture engine using AVAudioEngine.
// Converts input to 16kHz Mono Float32 in memory.

@preconcurrency import AVFoundation
import Foundation

enum AudioCaptureError: Error, LocalizedError {
    case permissionDenied
    case engineSetupFailed(String)
    case converterSetupFailed
    case noInputAvailable

    var errorDescription: String? {
        switch self {
        case .permissionDenied: return "Microphone access denied."
        case .engineSetupFailed(let detail): return "Engine setup failed: \(detail)"
        case .converterSetupFailed: return "Audio converter setup failed."
        case .noInputAvailable: return "No audio input available."
        }
    }
}

enum RecordingState: Equatable {
    case idle
    case recording
    case stopping
}

/// Target whisper.cpp format: 16kHz, Mono, Float32.
/// Module-level to be accessible from nonisolated contexts.
private let kWhisperAudioFormat = AVAudioFormat(
    commonFormat: .pcmFormatFloat32,
    sampleRate: 16_000,
    channels: 1,
    interleaved: false
)!

/// Real-time audio capture service.
@MainActor
@Observable
final class AudioCaptureService {

    private(set) var state: RecordingState = .idle
    private(set) var lastError: AudioCaptureError?

    static var whisperFormat: AVAudioFormat { kWhisperAudioFormat }

    private var audioEngine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var sampleBuffer: [Float] = []

    /// Intermediate conversion block size (frames at native rate).
    private let tapBufferSize: AVAudioFrameCount = 4096

    func startRecording() throws {
        guard state == .idle else { return }

        lastError = nil
        sampleBuffer.removeAll(keepingCapacity: true)

        try setupEngine()

        do {
            try audioEngine.start()
        } catch {
            audioEngine.reset()
            throw AudioCaptureError.engineSetupFailed(error.localizedDescription)
        }

        state = .recording
    }

    func stopRecording() -> [Float] {
        guard state == .recording else { return [] }

        state = .stopping
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        audioEngine.reset()

        let captured = sampleBuffer
        sampleBuffer.removeAll()
        state = .idle

        return captured
    }

    private func setupEngine() throws {
        audioEngine = AVAudioEngine()
        let inputNode = audioEngine.inputNode
        let nativeFormat = inputNode.outputFormat(forBus: 0)

        guard nativeFormat.sampleRate > 0, nativeFormat.channelCount > 0 else {
            throw AudioCaptureError.noInputAvailable
        }

        guard let conv = AVAudioConverter(from: nativeFormat, to: Self.whisperFormat) else {
            throw AudioCaptureError.converterSetupFailed
        }
        converter = conv

        let ratio = nativeFormat.sampleRate / Self.whisperFormat.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(Double(tapBufferSize) / ratio) + 1

        inputNode.installTap(onBus: 0, bufferSize: tapBufferSize, format: nativeFormat) { [weak self] buffer, _ in
            guard let self else { return }
            self.processTapBuffer(buffer, converter: conv, outputFrameCapacity: outputFrameCapacity)
        }
    }

    /// Appends native buffer to sampleBuffer as 16kHz Float32.
    private nonisolated func processTapBuffer(
        _ inputBuffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        outputFrameCapacity: AVAudioFrameCount
    ) {
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: kWhisperAudioFormat,
            frameCapacity: outputFrameCapacity
        ) else { return }

        var conversionError: NSError?
        // Use a reference-type box so the @Sendable closure can mutate it
        // without Swift 6 raising a captured-var warning.
        let provided = InputProvidedBox()

        let status = converter.convert(to: outputBuffer, error: &conversionError) { [inputBuffer] _, outStatus in
            if provided.value {
                outStatus.pointee = .noDataNow
                return nil
            }
            provided.value = true
            outStatus.pointee = .haveData
            return inputBuffer
        }

        guard status != .error, conversionError == nil,
              outputBuffer.frameLength > 0,
              let channelData = outputBuffer.floatChannelData?[0] else { return }

        let frameCount = Int(outputBuffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData, count: frameCount))

        MainActor.assumeIsolated {
            self.sampleBuffer.append(contentsOf: samples)
        }
    }
}

extension AudioCaptureService {
    var recordedDuration: Double {
        Double(sampleBuffer.count) / kWhisperAudioFormat.sampleRate
    }
}

/// Simple reference-type boolean box used to share mutable state
/// with a @Sendable converter callback without triggering Swift 6 warnings.
private final class InputProvidedBox: @unchecked Sendable {
    var value: Bool = false
}
