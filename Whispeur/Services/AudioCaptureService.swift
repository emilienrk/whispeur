// AudioCaptureService.swift
// Whispeur
//
// Moteur de capture audio pour Whispeur.
//
// Architecture :
//   - AVAudioEngine + tap sur inputNode : zéro I/O disque, tout en RAM.
//   - AVAudioConverter : downsampling temps-réel vers 16 000 Hz Mono Float32,
//     format exigé par whisper.cpp.
//   - Observable : permet à l'UI de réagir aux changements d'état sans KVO/delegate.
//
// Usage typique :
//   audioService.startRecording()
//   // ... l'utilisateur parle ...
//   let samples = await audioService.stopRecording()  // → [Float] prêts pour WhisperService

import AVFoundation
import Foundation

// MARK: - Erreurs

enum AudioCaptureError: Error, LocalizedError {
    case permissionDenied
    case engineSetupFailed(String)
    case converterSetupFailed
    case noInputAvailable

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "L'accès au microphone a été refusé. Autorisez Whispeur dans les Préférences Système."
        case .engineSetupFailed(let detail):
            return "Impossible de démarrer le moteur audio : \(detail)"
        case .converterSetupFailed:
            return "Impossible de créer le convertisseur audio (format non supporté)."
        case .noInputAvailable:
            return "Aucun périphérique d'entrée audio disponible."
        }
    }
}

// MARK: - État d'enregistrement

enum RecordingState: Equatable {
    case idle
    case recording
    case stopping
}

/// Format PCM imposé par whisper.cpp : 16 000 Hz, Mono, Float32.
/// Défini au niveau module pour être accessible depuis les contextes `nonisolated` (tap audio).
private let kWhisperAudioFormat = AVAudioFormat(
    commonFormat: .pcmFormatFloat32,
    sampleRate: 16_000,
    channels: 1,
    interleaved: false
)!

// MARK: - AudioCaptureService

/// Service de capture audio utilisant AVAudioEngine.
///
/// Capte le microphone via un tap sur `inputNode`, convertit le flux en temps réel
/// vers le format PCM 16 kHz Mono Float32 attendu par whisper.cpp, et accumule les
/// samples dans un buffer RAM. Zéro écriture disque.
///
/// Ce service est `@MainActor` pour que ses propriétés observables mettent à jour
/// l'UI correctement. La conversion audio est isolée dans une closure d'arrière-plan.
@MainActor
@Observable
final class AudioCaptureService {

    // MARK: - Propriétés observables

    /// État courant de l'enregistrement.
    private(set) var state: RecordingState = .idle

    /// Erreur éventuelle survenue lors de la capture.
    private(set) var lastError: AudioCaptureError?

    // MARK: - Format cible Whisper (accès public)

    /// Format PCM attendu par whisper.cpp : 16 000 Hz, Mono, Float32.
    /// Référence la constante module-level pour être accessible depuis l'extérieur.
    static var whisperFormat: AVAudioFormat { kWhisperAudioFormat }

    // MARK: - Internals

    private var audioEngine = AVAudioEngine()
    private var converter: AVAudioConverter?

    /// Buffer accumulant les samples Float32 en RAM pendant l'enregistrement.
    /// Protégé par l'isolation @MainActor : seules les mutations dans le tap (via
    /// `nonisolated` + explicit MainActor.run) sont autorisées.
    private var sampleBuffer: [Float] = []

    /// Taille du bloc de conversion intermédiaire (en frames @ format natif du micro).
    /// 4096 frames ≈ 85 ms @ 48 kHz — bon équilibre latence/charge CPU.
    private let tapBufferSize: AVAudioFrameCount = 4096

    // MARK: - API publique

    /// Lance l'enregistrement audio.
    ///
    /// - Precondition: La permission micro doit avoir été accordée avant cet appel.
    ///   Utilisez `MicrophonePermissionManager.request()` si nécessaire.
    /// - Throws: `AudioCaptureError` si l'engine ne peut pas démarrer.
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

    /// Arrête l'enregistrement et retourne les samples accumulés.
    ///
    /// - Returns: Tableau de `Float` PCM 16 kHz Mono, prêt pour `WhisperService.transcribe(samples:)`.
    func stopRecording() -> [Float] {
        guard state == .recording else { return [] }

        state = .stopping

        // Retire le tap et arrête le moteur
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        audioEngine.reset()

        let captured = sampleBuffer
        sampleBuffer.removeAll()
        state = .idle

        return captured
    }

    // MARK: - Setup interne

    private func setupEngine() throws {
        // Recréer l'engine pour repartir d'un état propre
        audioEngine = AVAudioEngine()
        let inputNode = audioEngine.inputNode

        // Format natif du microphone (ex : 48 kHz Stéréo Float32 sur Apple Silicon)
        let nativeFormat = inputNode.outputFormat(forBus: 0)

        guard nativeFormat.sampleRate > 0, nativeFormat.channelCount > 0 else {
            throw AudioCaptureError.noInputAvailable
        }

        // Crée le convertisseur natif → 16 kHz Mono Float32
        guard let conv = AVAudioConverter(from: nativeFormat, to: Self.whisperFormat) else {
            throw AudioCaptureError.converterSetupFailed
        }
        converter = conv

        // Ratio de downsampling (ex : 48000 / 16000 = 3.0)
        let ratio = nativeFormat.sampleRate / Self.whisperFormat.sampleRate

        // Taille du buffer de sortie (en frames @ 16 kHz)
        let outputFrameCapacity = AVAudioFrameCount(Double(tapBufferSize) / ratio) + 1

        // Installe le tap sur inputNode
        // La closure est appelée sur un thread audio interne (non-MainActor).
        // On capture `conv` et `outputFrameCapacity` par valeur pour thread-safety.
        inputNode.installTap(onBus: 0, bufferSize: tapBufferSize, format: nativeFormat) { [weak self] buffer, _ in
            guard let self else { return }
            self.processTapBuffer(buffer, converter: conv, outputFrameCapacity: outputFrameCapacity)
        }
    }

    /// Convertit un buffer natif en Float32 16 kHz et l'appende au sampleBuffer.
    /// Appelé sur le thread audio — accède à `sampleBuffer` via `MainActor.assumeIsolated`
    /// car cette méthode est appelée depuis le tap installé sur le MainActor.
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
        var inputProvided = false // flag pour le provider : on fournit l'input une seule fois

        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
            if inputProvided {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputProvided = true
            outStatus.pointee = .haveData
            return inputBuffer
        }

        guard status != .error, conversionError == nil,
              outputBuffer.frameLength > 0,
              let channelData = outputBuffer.floatChannelData?[0] else { return }

        // Copie les samples dans un tableau Swift (opération rapide, buffer court)
        let frameCount = Int(outputBuffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData, count: frameCount))

        // Append au sampleBuffer sur le MainActor
        MainActor.assumeIsolated {
            self.sampleBuffer.append(contentsOf: samples)
        }
    }
}

// MARK: - Extension: durée enregistrée

extension AudioCaptureService {
    /// Durée approximative du buffer accumulé, en secondes.
    var recordedDuration: Double {
        Double(sampleBuffer.count) / kWhisperAudioFormat.sampleRate
    }
}
