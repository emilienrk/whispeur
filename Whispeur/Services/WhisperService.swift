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

/// Main actor managing the whisper_context.
actor WhisperService {

    /// C pointer to the Whisper context.
    /// `nonisolated(unsafe)` allows deinit access. Safe because deinit implies exclusive access.
    nonisolated(unsafe) private var context: OpaquePointer?

    private var language: WhisperLanguage = .auto
    private var loadedModelPath: String?

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
    func loadModel(at url: URL, language: WhisperLanguage = .auto) throws {
        let path = url.path
        if loadedModelPath == path {
            self.language = language
            return
        }

        guard FileManager.default.fileExists(atPath: path) else {
            throw WhisperServiceError.modelNotFound(path: path)
        }

        _freeContext()

        var ctxParams = whisper_context_default_params()
        ctxParams.use_gpu = true
        ctxParams.flash_attn = true

        guard let newContext = whisper_init_from_file_with_params(path, ctxParams) else {
            throw WhisperServiceError.contextInitFailed(path: path)
        }

        context = newContext
        loadedModelPath = path
        self.language = language
    }

    func unloadModel() {
        _freeContext()
    }

    func setLanguage(_ language: WhisperLanguage) {
        self.language = language
    }

    var isModelLoaded: Bool { context != nil }

    /// Transcribes a 16kHz mono Float32 audio buffer.
    func transcribe(samples: [Float]) throws -> String {
        guard let ctx = context else { throw WhisperServiceError.noModelLoaded }

        // Leave 2 cores free, max 8 to prevent scaling issues.
        let maxThreads = max(1, min(8, ProcessInfo.processInfo.processorCount - 2))

        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.print_realtime = false
        params.print_progress = false
        params.print_timestamps = false
        params.print_special = false
        params.translate = false
        params.n_threads = Int32(maxThreads)
        params.offset_ms = 0
        params.no_context = true
        params.single_segment = false

        if let code = language.whisperCode {
            var result: Int32 = 0
            code.withCString { cCode in
                params.language = cCode
                samples.withUnsafeBufferPointer { buf in
                    result = whisper_full(ctx, params, buf.baseAddress, Int32(buf.count))
                }
            }
            if result != 0 { throw WhisperServiceError.transcriptionFailed }
        } else {
            params.language = nil
            var result: Int32 = 0
            samples.withUnsafeBufferPointer { buf in
                result = whisper_full(ctx, params, buf.baseAddress, Int32(buf.count))
            }
            if result != 0 { throw WhisperServiceError.transcriptionFailed }
        }

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
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        let hardcodedDev = URL(fileURLWithPath: "/Users/emilien/dev/perso/whispeur/Models/\(filename)")
        if FileManager.default.fileExists(atPath: hardcodedDev.path) {
            return hardcodedDev
        }

        return nil
    }
}
