// WhisperModel.swift
// Whispeur
//
// Data models for Whisper languages and ggml models.

import Foundation

// MARK: - Language

/// Represents a supported Whisper language.
struct WhisperLanguage: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    /// ISO 639-1 code for whisper_full_params.language. `nil` means auto-detect.
    let whisperCode: String?

    static let auto = WhisperLanguage(id: "auto", displayName: "Auto-detect", whisperCode: nil)

    static let all: [WhisperLanguage] = [
        .auto,
        WhisperLanguage(id: "af", displayName: "Afrikaans",          whisperCode: "af"),
        WhisperLanguage(id: "ar", displayName: "Arabic",             whisperCode: "ar"),
        WhisperLanguage(id: "hy", displayName: "Armenian",           whisperCode: "hy"),
        WhisperLanguage(id: "az", displayName: "Azerbaijani",        whisperCode: "az"),
        WhisperLanguage(id: "be", displayName: "Belarusian",         whisperCode: "be"),
        WhisperLanguage(id: "bs", displayName: "Bosnian",            whisperCode: "bs"),
        WhisperLanguage(id: "bg", displayName: "Bulgarian",          whisperCode: "bg"),
        WhisperLanguage(id: "ca", displayName: "Catalan",            whisperCode: "ca"),
        WhisperLanguage(id: "zh", displayName: "Chinese",            whisperCode: "zh"),
        WhisperLanguage(id: "hr", displayName: "Croatian",           whisperCode: "hr"),
        WhisperLanguage(id: "cs", displayName: "Czech",              whisperCode: "cs"),
        WhisperLanguage(id: "da", displayName: "Danish",             whisperCode: "da"),
        WhisperLanguage(id: "nl", displayName: "Dutch",              whisperCode: "nl"),
        WhisperLanguage(id: "en", displayName: "English",            whisperCode: "en"),
        WhisperLanguage(id: "et", displayName: "Estonian",           whisperCode: "et"),
        WhisperLanguage(id: "fi", displayName: "Finnish",            whisperCode: "fi"),
        WhisperLanguage(id: "fr", displayName: "French",             whisperCode: "fr"),
        WhisperLanguage(id: "gl", displayName: "Galician",           whisperCode: "gl"),
        WhisperLanguage(id: "de", displayName: "German",             whisperCode: "de"),
        WhisperLanguage(id: "el", displayName: "Greek",              whisperCode: "el"),
        WhisperLanguage(id: "he", displayName: "Hebrew",             whisperCode: "he"),
        WhisperLanguage(id: "hi", displayName: "Hindi",              whisperCode: "hi"),
        WhisperLanguage(id: "hu", displayName: "Hungarian",          whisperCode: "hu"),
        WhisperLanguage(id: "is", displayName: "Icelandic",          whisperCode: "is"),
        WhisperLanguage(id: "id", displayName: "Indonesian",         whisperCode: "id"),
        WhisperLanguage(id: "it", displayName: "Italian",            whisperCode: "it"),
        WhisperLanguage(id: "ja", displayName: "Japanese",           whisperCode: "ja"),
        WhisperLanguage(id: "kn", displayName: "Kannada",            whisperCode: "kn"),
        WhisperLanguage(id: "kk", displayName: "Kazakh",             whisperCode: "kk"),
        WhisperLanguage(id: "ko", displayName: "Korean",             whisperCode: "ko"),
        WhisperLanguage(id: "lv", displayName: "Latvian",            whisperCode: "lv"),
        WhisperLanguage(id: "lt", displayName: "Lithuanian",         whisperCode: "lt"),
        WhisperLanguage(id: "mk", displayName: "Macedonian",         whisperCode: "mk"),
        WhisperLanguage(id: "ms", displayName: "Malay",              whisperCode: "ms"),
        WhisperLanguage(id: "mi", displayName: "Maori",              whisperCode: "mi"),
        WhisperLanguage(id: "mr", displayName: "Marathi",            whisperCode: "mr"),
        WhisperLanguage(id: "ne", displayName: "Nepali",             whisperCode: "ne"),
        WhisperLanguage(id: "no", displayName: "Norwegian",          whisperCode: "no"),
        WhisperLanguage(id: "fa", displayName: "Persian",            whisperCode: "fa"),
        WhisperLanguage(id: "pl", displayName: "Polish",             whisperCode: "pl"),
        WhisperLanguage(id: "pt", displayName: "Portuguese",         whisperCode: "pt"),
        WhisperLanguage(id: "ro", displayName: "Romanian",           whisperCode: "ro"),
        WhisperLanguage(id: "ru", displayName: "Russian",            whisperCode: "ru"),
        WhisperLanguage(id: "sr", displayName: "Serbian",            whisperCode: "sr"),
        WhisperLanguage(id: "sk", displayName: "Slovak",             whisperCode: "sk"),
        WhisperLanguage(id: "sl", displayName: "Slovenian",          whisperCode: "sl"),
        WhisperLanguage(id: "es", displayName: "Spanish",            whisperCode: "es"),
        WhisperLanguage(id: "sw", displayName: "Swahili",            whisperCode: "sw"),
        WhisperLanguage(id: "sv", displayName: "Swedish",            whisperCode: "sv"),
        WhisperLanguage(id: "tl", displayName: "Tagalog",            whisperCode: "tl"),
        WhisperLanguage(id: "ta", displayName: "Tamil",              whisperCode: "ta"),
        WhisperLanguage(id: "th", displayName: "Thai",               whisperCode: "th"),
        WhisperLanguage(id: "tr", displayName: "Turkish",            whisperCode: "tr"),
        WhisperLanguage(id: "uk", displayName: "Ukrainian",          whisperCode: "uk"),
        WhisperLanguage(id: "ur", displayName: "Urdu",               whisperCode: "ur"),
        WhisperLanguage(id: "vi", displayName: "Vietnamese",         whisperCode: "vi"),
        WhisperLanguage(id: "cy", displayName: "Welsh",              whisperCode: "cy"),
    ]

    static func find(byCode code: String) -> WhisperLanguage {
        all.first { $0.id == code } ?? .auto
    }
}

// MARK: - GGML Model

/// Descriptor for a downloadable ggml model.
struct WhisperModelDescriptor: Identifiable, Hashable, Sendable {
    let name: String
    let sizeInfo: String
    let downloadURL: URL
    let filename: String
    let isEnglishOnly: Bool

    var id: String { name }

    /// Local path in Application Support.
    var localURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Whispeur/Models/\(filename)")
    }

    var isDownloaded: Bool {
        FileManager.default.fileExists(atPath: localURL.path)
    }

    static let catalog: [WhisperModelDescriptor] = [
        .init(name: "tiny",           sizeInfo: "F16 · 75 MiB",    ggmlFile: "ggml-tiny.bin",               englishOnly: false),
        .init(name: "tiny-q5_1",      sizeInfo: "Q5_1 · 31 MiB",   ggmlFile: "ggml-tiny-q5_1.bin",          englishOnly: false),
        .init(name: "tiny-q8_0",      sizeInfo: "Q8_0 · 42 MiB",   ggmlFile: "ggml-tiny-q8_0.bin",          englishOnly: false),
        .init(name: "tiny.en",        sizeInfo: "F16 · 75 MiB",    ggmlFile: "ggml-tiny.en.bin",             englishOnly: true),
        .init(name: "tiny.en-q5_1",   sizeInfo: "Q5_1 · 31 MiB",   ggmlFile: "ggml-tiny.en-q5_1.bin",       englishOnly: true),
        .init(name: "tiny.en-q8_0",   sizeInfo: "Q8_0 · 42 MiB",   ggmlFile: "ggml-tiny.en-q8_0.bin",       englishOnly: true),
        .init(name: "base",           sizeInfo: "F16 · 142 MiB",   ggmlFile: "ggml-base.bin",               englishOnly: false),
        .init(name: "base-q5_1",      sizeInfo: "Q5_1 · 57 MiB",   ggmlFile: "ggml-base-q5_1.bin",          englishOnly: false),
        .init(name: "base-q8_0",      sizeInfo: "Q8_0 · 78 MiB",   ggmlFile: "ggml-base-q8_0.bin",          englishOnly: false),
        .init(name: "base.en",        sizeInfo: "F16 · 142 MiB",   ggmlFile: "ggml-base.en.bin",             englishOnly: true),
        .init(name: "base.en-q5_1",   sizeInfo: "Q5_1 · 57 MiB",   ggmlFile: "ggml-base.en-q5_1.bin",       englishOnly: true),
        .init(name: "base.en-q8_0",   sizeInfo: "Q8_0 · 78 MiB",   ggmlFile: "ggml-base.en-q8_0.bin",       englishOnly: true),
        .init(name: "small",          sizeInfo: "F16 · 466 MiB",   ggmlFile: "ggml-small.bin",              englishOnly: false),
        .init(name: "small-q5_1",     sizeInfo: "Q5_1 · 181 MiB",  ggmlFile: "ggml-small-q5_1.bin",         englishOnly: false),
        .init(name: "small-q8_0",     sizeInfo: "Q8_0 · 252 MiB",  ggmlFile: "ggml-small-q8_0.bin",         englishOnly: false),
        .init(name: "small.en",       sizeInfo: "F16 · 466 MiB",   ggmlFile: "ggml-small.en.bin",            englishOnly: true),
        .init(name: "small.en-q5_1",  sizeInfo: "Q5_1 · 181 MiB",  ggmlFile: "ggml-small.en-q5_1.bin",      englishOnly: true),
        .init(name: "small.en-q8_0",  sizeInfo: "Q8_0 · 252 MiB",  ggmlFile: "ggml-small.en-q8_0.bin",      englishOnly: true),
        .init(name: "medium",            sizeInfo: "F16 · 1.5 GiB",  ggmlFile: "ggml-medium.bin",           englishOnly: false),
        .init(name: "medium-q5_0",       sizeInfo: "Q5_0 · 514 MiB", ggmlFile: "ggml-medium-q5_0.bin",      englishOnly: false),
        .init(name: "medium-q8_0",       sizeInfo: "Q8_0 · 785 MiB", ggmlFile: "ggml-medium-q8_0.bin",      englishOnly: false),
        .init(name: "medium.en",         sizeInfo: "F16 · 1.5 GiB",  ggmlFile: "ggml-medium.en.bin",         englishOnly: true),
        .init(name: "medium.en-q5_0",    sizeInfo: "Q5_0 · 514 MiB", ggmlFile: "ggml-medium.en-q5_0.bin",   englishOnly: true),
        .init(name: "medium.en-q8_0",    sizeInfo: "Q8_0 · 785 MiB", ggmlFile: "ggml-medium.en-q8_0.bin",   englishOnly: true),
        .init(name: "large-v1",          sizeInfo: "F16 · 2.9 GiB",  ggmlFile: "ggml-large.bin",             englishOnly: false),
        .init(name: "large-v2",          sizeInfo: "F16 · 2.9 GiB",  ggmlFile: "ggml-large-v2.bin",          englishOnly: false),
        .init(name: "large-v2-q5_0",     sizeInfo: "Q5_0 · 1.1 GiB", ggmlFile: "ggml-large-v2-q5_0.bin",    englishOnly: false),
        .init(name: "large-v2-q8_0",     sizeInfo: "Q8_0 · 1.5 GiB", ggmlFile: "ggml-large-v2-q8_0.bin",    englishOnly: false),
        .init(name: "large-v3",          sizeInfo: "F16 · 2.9 GiB",  ggmlFile: "ggml-large-v3.bin",          englishOnly: false),
        .init(name: "large-v3-q5_0",     sizeInfo: "Q5_0 · 1.1 GiB", ggmlFile: "ggml-large-v3-q5_0.bin",    englishOnly: false),
        .init(name: "large-v3-turbo",      sizeInfo: "F16 · 1.5 GiB",  ggmlFile: "ggml-large-v3-turbo.bin",      englishOnly: false),
        .init(name: "large-v3-turbo-q5_0", sizeInfo: "Q5_0 · 547 MiB", ggmlFile: "ggml-large-v3-turbo-q5_0.bin", englishOnly: false),
        .init(name: "large-v3-turbo-q8_0", sizeInfo: "Q8_0 · 834 MiB", ggmlFile: "ggml-large-v3-turbo-q8_0.bin", englishOnly: false),
    ]

    static var testModel: WhisperModelDescriptor {
        catalog.first { $0.name == "base" }!
    }
}

private let huggingFaceBase = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/"

private extension WhisperModelDescriptor {
    init(name: String, sizeInfo: String, ggmlFile filename: String, englishOnly: Bool) {
        self.name = name
        self.sizeInfo = sizeInfo
        self.filename = filename
        self.downloadURL = URL(string: huggingFaceBase + filename)!
        self.isEnglishOnly = englishOnly
    }
}
