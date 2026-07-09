// WhisperService.swift
// Whispeur
//
// Swift actor bridging the whisper.cpp C library.
// Ensures thread safety for the C API (exclusive access per context).

import Foundation

enum WhisperServiceError: Error, LocalizedError {
    case modelNotFound(path: String)
    case contextInitFailed(path: String)
    case transcriptionFailed
    case noModelLoaded

    var errorDescription: String? {
        switch self {
        case .modelNotFound(let path): return "Model not found: \(path)"
        case .contextInitFailed(let path): return "Failed to init context for: \(path)"
        case .transcriptionFailed: return "Transcription failed."
        case .noModelLoaded: return "No model loaded. Call loadModel() first."
        }
    }
}

// MARK: - Engine configuration (passed from AppSettings, Sendable-safe value type)

struct WhisperEngineConfig: Sendable {
    var useBeamSearch: Bool
    var beamSize: Int
    var temperature: Float
    var noSpeechThreshold: Float
    var conditionOnPreviousText: Bool
    var useGPU: Bool
    var initialPrompt: String

    static let `default` = WhisperEngineConfig(
        useBeamSearch: false,
        beamSize: 5,
        temperature: 0.0,
        noSpeechThreshold: 0.6,
        conditionOnPreviousText: false,
        useGPU: true,
        initialPrompt: ""
    )
}

/// Main actor managing the whisper_context.
actor WhisperService {

    /// C pointer to the Whisper context.
    /// `nonisolated(unsafe)` allows deinit access. Safe because deinit implies exclusive access.
    nonisolated(unsafe) private var context: OpaquePointer?

    private var language: WhisperLanguage = .auto
    private var loadedModelPath: String?
    private var loadedWithGPU: Bool = true

    init() {}

    deinit {
        if let ctx = context { whisper_free(ctx) }
    }

    private func _freeContext() {
        if let ctx = context {
            whisper_free(ctx)
            context = nil
            loadedModelPath = nil
        }
    }

    /// Loads a ggml model, replacing the previous one if needed.
    func loadModel(at url: URL, language: WhisperLanguage = .auto, useGPU: Bool = true) throws {
        let path = url.path(percentEncoded: false)
        // Reload if path or GPU flag changed.
        if loadedModelPath == path && loadedWithGPU == useGPU {
            self.language = language
            return
        }

        guard FileManager.default.fileExists(atPath: path) else {
            throw WhisperServiceError.modelNotFound(path: path)
        }

        _freeContext()

        var ctxParams = whisper_context_default_params()
        ctxParams.use_gpu = useGPU
        ctxParams.flash_attn = true

        guard let newContext = whisper_init_from_file_with_params(path, ctxParams) else {
            throw WhisperServiceError.contextInitFailed(path: path)
        }

        context = newContext
        loadedModelPath = path
        loadedWithGPU = useGPU
        self.language = language
    }

    func unloadModel() {
        _freeContext()
    }

    func setLanguage(_ language: WhisperLanguage) {
        self.language = language
    }

    var isModelLoaded: Bool { context != nil }

    /// Transcribes a 16kHz mono Float32 audio buffer using the provided engine config.
    func transcribe(samples: [Float], config: WhisperEngineConfig = .default) throws -> String {
        guard let ctx = context else { throw WhisperServiceError.noModelLoaded }

        // Leave 2 cores free, max 8 to prevent scaling issues.
        let maxThreads = max(1, min(8, ProcessInfo.processInfo.processorCount - 2))

        let strategy: whisper_sampling_strategy = config.useBeamSearch
            ? WHISPER_SAMPLING_BEAM_SEARCH
            : WHISPER_SAMPLING_GREEDY

        var params = whisper_full_default_params(strategy)
        params.print_realtime   = false
        params.print_progress   = false
        params.print_timestamps = false
        params.print_special    = false
        params.translate        = false
        params.n_threads        = Int32(maxThreads)
        params.offset_ms        = 0
        params.no_context       = !config.conditionOnPreviousText
        params.single_segment   = false
        params.temperature      = config.temperature
        params.no_speech_thold  = config.noSpeechThreshold
        if config.useBeamSearch {
            params.beam_search.beam_size = Int32(config.beamSize)
        }

        // Les chaînes C doivent survivre à whisper_full : strdup + defer free
        // évite l'imbrication de withCString pour plusieurs chaînes optionnelles.
        let cLanguage: UnsafeMutablePointer<CChar>? = language.whisperCode.flatMap { strdup($0) }
        let cPrompt: UnsafeMutablePointer<CChar>? = config.initialPrompt.isEmpty ? nil : strdup(config.initialPrompt)
        defer {
            free(cLanguage)
            free(cPrompt)
        }
        params.language = UnsafePointer(cLanguage)
        params.initial_prompt = UnsafePointer(cPrompt)

        var result: Int32 = 0
        samples.withUnsafeBufferPointer { buf in
            result = whisper_full(ctx, params, buf.baseAddress, Int32(buf.count))
        }
        if result != 0 { throw WhisperServiceError.transcriptionFailed }

        return extractTranscription(from: ctx)
    }

    private func extractTranscription(from ctx: OpaquePointer) -> String {
        let segmentCount: Int32 = whisper_full_n_segments(ctx)
        guard segmentCount > 0 else { return "" }

        var result = ""
        result.reserveCapacity(Int(segmentCount) * 40)

        for i: Int32 in 0..<segmentCount {
            if let cStr = whisper_full_get_segment_text(ctx, i) {
                result += String(cString: cStr)
            }
        }

        return result.trimmingCharacters(in: .whitespaces)
    }

    /// Resolves the bundled dev model URL.
    static func devModelURL(filename: String = "ggml-base.bin") -> URL? {
        if let bundleURL = Bundle.main.url(forResource: filename, withExtension: nil) {
            return bundleURL
        }

        let executableURL = Bundle.main.executableURL
        let projectModelsURL = executableURL?
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        if let base = projectModelsURL {
            let candidate = base.appendingPathComponent("Models/\(filename)")
            if FileManager.default.fileExists(atPath: candidate.path(percentEncoded: false)) {
                return candidate
            }
        }

        let hardcodedDev = URL(fileURLWithPath: "/Users/emilien/dev/perso/whispeur/Models/\(filename)")
        if FileManager.default.fileExists(atPath: hardcodedDev.path(percentEncoded: false)) {
            return hardcodedDev
        }

        return nil
    }
}
