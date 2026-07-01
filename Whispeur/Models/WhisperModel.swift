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
        WhisperLanguage(id: "ar", displayName: "Arabe",              whisperCode: "ar"),
        WhisperLanguage(id: "hy", displayName: "Arménien",           whisperCode: "hy"),
        WhisperLanguage(id: "az", displayName: "Azerbaïdjanais",     whisperCode: "az"),
        WhisperLanguage(id: "be", displayName: "Biélorusse",         whisperCode: "be"),
        WhisperLanguage(id: "bs", displayName: "Bosniaque",          whisperCode: "bs"),
        WhisperLanguage(id: "bg", displayName: "Bulgare",            whisperCode: "bg"),
        WhisperLanguage(id: "ca", displayName: "Catalan",            whisperCode: "ca"),
        WhisperLanguage(id: "zh", displayName: "Chinois",            whisperCode: "zh"),
        WhisperLanguage(id: "hr", displayName: "Croate",             whisperCode: "hr"),
        WhisperLanguage(id: "cs", displayName: "Tchèque",            whisperCode: "cs"),
        WhisperLanguage(id: "da", displayName: "Danois",             whisperCode: "da"),
        WhisperLanguage(id: "nl", displayName: "Néerlandais",        whisperCode: "nl"),
        WhisperLanguage(id: "en", displayName: "Anglais",            whisperCode: "en"),
        WhisperLanguage(id: "et", displayName: "Estonien",           whisperCode: "et"),
        WhisperLanguage(id: "fi", displayName: "Finnois",            whisperCode: "fi"),
        WhisperLanguage(id: "fr", displayName: "Français",           whisperCode: "fr"),
        WhisperLanguage(id: "gl", displayName: "Galicien",           whisperCode: "gl"),
        WhisperLanguage(id: "de", displayName: "Allemand",           whisperCode: "de"),
        WhisperLanguage(id: "el", displayName: "Grec",               whisperCode: "el"),
        WhisperLanguage(id: "he", displayName: "Hébreu",             whisperCode: "he"),
        WhisperLanguage(id: "hi", displayName: "Hindi",              whisperCode: "hi"),
        WhisperLanguage(id: "hu", displayName: "Hongrois",           whisperCode: "hu"),
        WhisperLanguage(id: "is", displayName: "Islandais",          whisperCode: "is"),
        WhisperLanguage(id: "id", displayName: "Indonésien",         whisperCode: "id"),
        WhisperLanguage(id: "it", displayName: "Italien",            whisperCode: "it"),
        WhisperLanguage(id: "ja", displayName: "Japonais",           whisperCode: "ja"),
        WhisperLanguage(id: "kn", displayName: "Kannada",            whisperCode: "kn"),
        WhisperLanguage(id: "kk", displayName: "Kazakh",             whisperCode: "kk"),
        WhisperLanguage(id: "ko", displayName: "Coréen",             whisperCode: "ko"),
        WhisperLanguage(id: "lv", displayName: "Letton",             whisperCode: "lv"),
        WhisperLanguage(id: "lt", displayName: "Lituanien",          whisperCode: "lt"),
        WhisperLanguage(id: "mk", displayName: "Macédonien",         whisperCode: "mk"),
        WhisperLanguage(id: "ms", displayName: "Malais",             whisperCode: "ms"),
        WhisperLanguage(id: "mi", displayName: "Maori",              whisperCode: "mi"),
        WhisperLanguage(id: "mr", displayName: "Marathi",            whisperCode: "mr"),
        WhisperLanguage(id: "ne", displayName: "Népalais",           whisperCode: "ne"),
        WhisperLanguage(id: "no", displayName: "Norvégien",          whisperCode: "no"),
        WhisperLanguage(id: "fa", displayName: "Persan",             whisperCode: "fa"),
        WhisperLanguage(id: "pl", displayName: "Polonais",           whisperCode: "pl"),
        WhisperLanguage(id: "pt", displayName: "Portugais",          whisperCode: "pt"),
        WhisperLanguage(id: "ro", displayName: "Roumain",            whisperCode: "ro"),
        WhisperLanguage(id: "ru", displayName: "Russe",              whisperCode: "ru"),
        WhisperLanguage(id: "sr", displayName: "Serbe",              whisperCode: "sr"),
        WhisperLanguage(id: "sk", displayName: "Slovaque",           whisperCode: "sk"),
        WhisperLanguage(id: "sl", displayName: "Slovène",            whisperCode: "sl"),
        WhisperLanguage(id: "es", displayName: "Espagnol",           whisperCode: "es"),
        WhisperLanguage(id: "sw", displayName: "Swahili",            whisperCode: "sw"),
        WhisperLanguage(id: "sv", displayName: "Suédois",            whisperCode: "sv"),
        WhisperLanguage(id: "tl", displayName: "Tagalog",            whisperCode: "tl"),
        WhisperLanguage(id: "ta", displayName: "Tamoul",             whisperCode: "ta"),
        WhisperLanguage(id: "th", displayName: "Thaï",               whisperCode: "th"),
        WhisperLanguage(id: "tr", displayName: "Turc",               whisperCode: "tr"),
        WhisperLanguage(id: "uk", displayName: "Ukrainien",          whisperCode: "uk"),
        WhisperLanguage(id: "ur", displayName: "Ourdou",             whisperCode: "ur"),
        WhisperLanguage(id: "vi", displayName: "Vietnamien",         whisperCode: "vi"),
        WhisperLanguage(id: "cy", displayName: "Gallois",            whisperCode: "cy"),
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
        FileManager.default.fileExists(atPath: localURL.path(percentEncoded: false))
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
