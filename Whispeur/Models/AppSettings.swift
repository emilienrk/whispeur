// AppSettings.swift
// Whispeur
//
// Centralized persistent preferences backed by UserDefaults.
// All stored properties are in-memory so @Observable can track mutations.
// Each didSet syncs to UserDefaults for persistence.

import Foundation

@MainActor
@Observable
final class AppSettings {

    // MARK: - Singleton

    static let shared = AppSettings()

    // MARK: - Init (load from UserDefaults)

    private init() {
        let ud = UserDefaults.standard
        hotKeyCode             = (ud.integer(forKey: "hotKeyCode").nonZero) ?? 61
        hotKeyModifiers        = ud.integer(forKey: "hotKeyModifiers")
        _hotKeyModeRaw         = ud.string(forKey: "hotKeyMode") ?? HotKeyMode.pushToTalk.rawValue
        selectedModelFilename  = ud.string(forKey: "selectedModel") ?? "ggml-base.bin"
        languageCode           = ud.string(forKey: "language") ?? "auto"
        _autoPasteEnabled      = (ud.object(forKey: "autoPaste") as? Bool) ?? true
        if let data = ud.data(forKey: "favoritedModels"),
           let arr  = try? JSONDecoder().decode([String].self, from: data) {
            favoritedModelFilenames = arr
        } else {
            favoritedModelFilenames = []
        }
    }

    // MARK: - Hotkey (stored in-memory, persisted on write)

    var hotKeyCode: Int {
        didSet { UserDefaults.standard.set(hotKeyCode, forKey: "hotKeyCode") }
    }
    var hotKeyModifiers: Int {
        didSet { UserDefaults.standard.set(hotKeyModifiers, forKey: "hotKeyModifiers") }
    }

    private var _hotKeyModeRaw: String {
        didSet { UserDefaults.standard.set(_hotKeyModeRaw, forKey: "hotKeyMode") }
    }
    var hotKeyMode: HotKeyMode {
        get { HotKeyMode(rawValue: _hotKeyModeRaw) ?? .pushToTalk }
        set { _hotKeyModeRaw = newValue.rawValue }
    }

    // MARK: - Model

    var selectedModelFilename: String {
        didSet { UserDefaults.standard.set(selectedModelFilename, forKey: "selectedModel") }
    }

    var selectedModelDescriptor: WhisperModelDescriptor? {
        WhisperModelDescriptor.catalog.first { $0.filename == selectedModelFilename }
    }

    var selectedModelURL: URL? {
        selectedModelDescriptor?.localURL
    }

    // MARK: - Language

    var languageCode: String {
        didSet { UserDefaults.standard.set(languageCode, forKey: "language") }
    }

    var selectedLanguage: WhisperLanguage {
        get { WhisperLanguage.find(byCode: languageCode) }
        set { languageCode = newValue.id }
    }

    // MARK: - Auto-paste

    private var _autoPasteEnabled: Bool {
        didSet { UserDefaults.standard.set(_autoPasteEnabled, forKey: "autoPaste") }
    }
    var autoPasteEnabled: Bool {
        get { _autoPasteEnabled }
        set { _autoPasteEnabled = newValue }
    }

    // MARK: - Favoris de modèles (max 4)

    static let maxFavorites = 4

    /// In-memory array tracked by @Observable — persisted to UserDefaults on each write.
    var favoritedModelFilenames: [String] {
        didSet {
            let data = try? JSONEncoder().encode(favoritedModelFilenames)
            UserDefaults.standard.set(data, forKey: "favoritedModels")
        }
    }

    func toggleFavorite(filename: String) {
        var current = favoritedModelFilenames
        if let idx = current.firstIndex(of: filename) {
            current.remove(at: idx)
        } else if current.count < AppSettings.maxFavorites {
            current.append(filename)
        }
        favoritedModelFilenames = current
    }

    func isFavorite(filename: String) -> Bool {
        favoritedModelFilenames.contains(filename)
    }

    var favoritedModelDescriptors: [WhisperModelDescriptor] {
        favoritedModelFilenames.compactMap { fn in
            WhisperModelDescriptor.catalog.first { $0.filename == fn }
        }
    }

    // MARK: - Derived helpers

    var currentHotKey: HotKey {
        HotKey(keyCode: hotKeyCode, modifiers: hotKeyModifiers)
    }
}

private extension Int {
    var nonZero: Int? { self != 0 ? self : nil }
}
