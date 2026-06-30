// AudioCaptureService.swift
// Whispeur
//
// Audio capture engine using AVAudioEngine.
// Converts input to 16kHz Mono Float32 in memory.
//
// THREAD MODEL:
// - startRecording / stopRecording run on @MainActor.
// - installTap callback fires on AVFoundation’s realtime thread.
// - We accumulate samples in a thread-safe box (lock-protected),
//   then drain into sampleBuffer in stopRecording() on the main actor.
//   MainActor.assumeIsolated is NEVER called from the realtime thread.

@preconcurrency import AVFoundation
import Foundation
import os

fileprivate let logger = Logger(subsystem: "com.whispeur", category: "AudioCapture")

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
private let kWhisperAudioFormat = AVAudioFormat(
    commonFormat: .pcmFormatFloat32,
    sampleRate: 16_000,
    channels: 1,
    interleaved: false
)!

/// Thread-safe accumulator for realtime audio samples.
/// Appended on AVFoundation realtime thread, drained on MainActor.
final class SamplesAccumulator: @unchecked Sendable {
    private var lock = os_unfair_lock()
    private var buffer: [Float] = []

    func append(_ samples: [Float]) {
        os_unfair_lock_lock(&lock)
        buffer.append(contentsOf: samples)
        os_unfair_lock_unlock(&lock)
    }

    func drainAll() -> [Float] {
        os_unfair_lock_lock(&lock)
        let result = buffer
        buffer.removeAll(keepingCapacity: true)
        os_unfair_lock_unlock(&lock)
        return result
    }
}

/// Real-time audio capture service.
@MainActor
@Observable
final class AudioCaptureService {

    private(set) var state: RecordingState = .idle
    private(set) var lastError: AudioCaptureError?

    static var whisperFormat: AVAudioFormat { kWhisperAudioFormat }

    private var audioEngine = AVAudioEngine()
    private var converter: AVAudioConverter?
    /// Thread-safe accumulator — written from realtime tap, drained in stopRecording().
    private let accumulator = SamplesAccumulator()

    private let tapBufferSize: AVAudioFrameCount = 4096

    func startRecording() throws {
        guard state == .idle else {
            print("[AudioCapture] startRecording() skipped — already in state: \(state)")
            return
        }

        lastError = nil
        // Drain any leftover samples from a previous session.
        _ = accumulator.drainAll()

        try setupEngine()

        do {
            try audioEngine.start()
        } catch {
            audioEngine.reset()
            print("[AudioCapture] Engine start failed: \(error)")
            throw AudioCaptureError.engineSetupFailed(error.localizedDescription)
        }

        state = .recording
        print("[AudioCapture] Recording started 🎤")
    }

    func stopRecording() -> [Float] {
        guard state == .recording else {
            print("[AudioCapture] stopRecording() skipped — not recording (state=\(state))")
            return []
        }

        state = .stopping
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        audioEngine.reset()

        // Drain accumulated samples on the MainActor (safe).
        let captured = accumulator.drainAll()
        state = .idle
        print("[AudioCapture] Recording stopped. Captured \(captured.count) samples (\(String(format: "%.2f", Double(captured.count) / 16000.0))s) 🔴")
        return captured
    }

    private func setupEngine() throws {
        audioEngine = AVAudioEngine()
        let inputNode = audioEngine.inputNode
        let nativeFormat = inputNode.outputFormat(forBus: 0)

        guard nativeFormat.sampleRate > 0, nativeFormat.channelCount > 0 else {
            print("[AudioCapture] No audio input available (sampleRate=\(nativeFormat.sampleRate) channels=\(nativeFormat.channelCount))")
            throw AudioCaptureError.noInputAvailable
        }

        print("[AudioCapture] Native format: \(nativeFormat.sampleRate)Hz \(nativeFormat.channelCount)ch")

        guard let conv = AVAudioConverter(from: nativeFormat, to: Self.whisperFormat) else {
            print("[AudioCapture] AVAudioConverter init failed")
            throw AudioCaptureError.converterSetupFailed
        }
        converter = conv

        let ratio = nativeFormat.sampleRate / Self.whisperFormat.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(Double(tapBufferSize) / ratio) + 1

        let tapBlock = Self.createTapBlock(
            converter: conv,
            outputFrameCapacity: outputFrameCapacity,
            accumulator: accumulator
        )

        inputNode.installTap(onBus: 0, bufferSize: tapBufferSize, format: nativeFormat, block: tapBlock)
    }

    /// Creates the tap closure in a strictly nonisolated context.
    /// This prevents Swift 6 from implicitly inheriting @MainActor isolation for the closure,
    /// which would cause a crash when AVFoundation calls it from `RealtimeMessenger.mServiceQueue`.
    nonisolated private static func createTapBlock(
        converter: AVAudioConverter,
        outputFrameCapacity: AVAudioFrameCount,
        accumulator: SamplesAccumulator
    ) -> AVAudioNodeTapBlock {
        return { buffer, _ in
            AudioCaptureService.convertAndAccumulate(
                buffer,
                converter: converter,
                outputFrameCapacity: outputFrameCapacity,
                into: accumulator
            )
        }
    }

    /// Converts a native-format buffer to 16kHz Float32 and appends to the accumulator.
    /// Static + nonisolated: never touches MainActor state.
    nonisolated private static func convertAndAccumulate(
        _ inputBuffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        outputFrameCapacity: AVAudioFrameCount,
        into accumulator: SamplesAccumulator
    ) {
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: kWhisperAudioFormat,
            frameCapacity: outputFrameCapacity
        ) else { return }

        var conversionError: NSError?
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
        accumulator.append(samples)
    }
}

extension AudioCaptureService {
    var recordedDuration: Double {
        // Note: reads accumulator (not thread-safe for precision, but fine for display).
        Double(accumulator.drainAll().count) / kWhisperAudioFormat.sampleRate
    }
}

/// Simple reference-type boolean box used to share mutable state
/// with a @Sendable converter callback without triggering Swift 6 warnings.
private final class InputProvidedBox: @unchecked Sendable {
    var value: Bool = false
}
