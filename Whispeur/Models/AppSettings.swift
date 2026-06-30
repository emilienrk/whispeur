// AppSettings.swift
// Whispeur
//
// Centralized persistent preferences backed by UserDefaults (@AppStorage).

import Foundation

@MainActor
@Observable
final class AppSettings {

    // MARK: - Singleton

    static let shared = AppSettings()

    // MARK: - Hotkey

    var hotKeyCode: Int {
        get { _hotKeyCode }
        set { _hotKeyCode = newValue }
    }
    var hotKeyModifiers: Int {
        get { _hotKeyModifiers }
        set { _hotKeyModifiers = newValue }
    }
    var hotKeyMode: HotKeyMode {
        get { HotKeyMode(rawValue: _hotKeyModeRaw) ?? .pushToTalk }
        set { _hotKeyModeRaw = newValue.rawValue }
    }

    // MARK: - Model

    /// Filename of the selected ggml model (e.g. "ggml-base.bin")
    var selectedModelFilename: String {
        get { _selectedModelFilename }
        set { _selectedModelFilename = newValue }
    }

    var selectedModelDescriptor: WhisperModelDescriptor? {
        WhisperModelDescriptor.catalog.first { $0.filename == selectedModelFilename }
    }

    var selectedModelURL: URL? {
        selectedModelDescriptor?.localURL
    }

    // MARK: - Language

    var languageCode: String {
        get { _languageCode }
        set { _languageCode = newValue }
    }

    var selectedLanguage: WhisperLanguage {
        get { WhisperLanguage.find(byCode: languageCode) }
        set { languageCode = newValue.id }
    }

    // MARK: - Auto-paste

    var autoPasteEnabled: Bool {
        get { _autoPasteEnabled }
        set { _autoPasteEnabled = newValue }
    }

    // MARK: - Favoris de modèles (max 4)

    static let maxFavorites = 4

    var favoritedModelFilenames: [String] {
        get { _favoritedModelFilenames }
        set { _favoritedModelFilenames = newValue }
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

    // MARK: - Private storage (UserDefaults-backed)

    private var _hotKeyCode: Int {
        get { UserDefaults.standard.integer(forKey: "hotKeyCode").nonZero ?? 61 }
        set { UserDefaults.standard.set(newValue, forKey: "hotKeyCode") }
    }
    private var _hotKeyModifiers: Int {
        get { UserDefaults.standard.integer(forKey: "hotKeyModifiers") }
        set { UserDefaults.standard.set(newValue, forKey: "hotKeyModifiers") }
    }
    private var _hotKeyModeRaw: String {
        get { UserDefaults.standard.string(forKey: "hotKeyMode") ?? HotKeyMode.pushToTalk.rawValue }
        set { UserDefaults.standard.set(newValue, forKey: "hotKeyMode") }
    }
    private var _selectedModelFilename: String {
        get { UserDefaults.standard.string(forKey: "selectedModel") ?? "ggml-base.bin" }
        set { UserDefaults.standard.set(newValue, forKey: "selectedModel") }
    }
    private var _languageCode: String {
        get { UserDefaults.standard.string(forKey: "language") ?? "auto" }
        set { UserDefaults.standard.set(newValue, forKey: "language") }
    }
    private var _autoPasteEnabled: Bool {
        get {
            let stored = UserDefaults.standard.object(forKey: "autoPaste")
            return stored as? Bool ?? true
        }
        set { UserDefaults.standard.set(newValue, forKey: "autoPaste") }
    }
    private var _favoritedModelFilenames: [String] {
        get {
            guard let data = UserDefaults.standard.data(forKey: "favoritedModels"),
                  let arr = try? JSONDecoder().decode([String].self, from: data) else { return [] }
            return arr
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            UserDefaults.standard.set(data, forKey: "favoritedModels")
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
