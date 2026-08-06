// SystemSoundLibrary.swift
// Whispeur
//
// Lists the alert sounds macOS itself offers, and plays them.
//
// The directories and their precedence are the ones System Settings › Sound ›
// Alert sound uses, so a sound dropped in ~/Library/Sounds appears in Whispeur
// exactly as it does in the system list — no import step, no copy of our own.

import Foundation
import AudioToolbox

/// Searched least-specific first, so a user sound shadows a system one of the
/// same name. That is the order System Settings resolves them in.
let soundSearchPaths: [String] = [
    "/System/Library/Sounds",
    "/Library/Sounds",
    NSHomeDirectory() + "/Library/Sounds",
]

/// Extensions macOS accepts in a Sounds directory. AIFF is what ships with the
/// system; the others are what users actually drop in there.
private let soundExtensions: Set<String> = ["aiff", "aif", "wav", "caf", "m4a", "mp3"]

/// Sound names — file names without extension — offered by `directories`,
/// deduplicated and sorted the way the system list presents them.
///
/// A missing directory is skipped rather than treated as an error: /Library and
/// ~/Library/Sounds do not exist on a fresh system.
func soundNames(in directories: [String], fileManager: FileManager = .default) -> [String] {
    var names: Set<String> = []
    for directory in directories {
        let entries = (try? fileManager.contentsOfDirectory(atPath: directory)) ?? []
        for entry in entries where soundExtensions.contains((entry as NSString).pathExtension.lowercased()) {
            names.insert((entry as NSString).deletingPathExtension)
        }
    }
    return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
}

/// The file backing `name`, resolved with the same precedence as the list: the
/// last directory holding it wins, so a user sound overrides a system one.
func soundURL(named name: String, in directories: [String], fileManager: FileManager = .default) -> URL? {
    var found: URL?
    for directory in directories {
        for ext in soundExtensions {
            let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name).\(ext)")
            if fileManager.fileExists(atPath: url.path(percentEncoded: false)) { found = url }
        }
    }
    return found
}

// MARK: - Playback

@MainActor
enum SystemSoundLibrary {

    /// Sounds offered in the settings pickers.
    static var availableNames: [String] { soundNames(in: soundSearchPaths) }

    /// Plays `name` as an alert, so the system applies System Settings › Sound ›
    /// Alert volume. NSSound would ignore that slider and play at full output
    /// volume, far too loud for a cue that fires on every dictation.
    ///
    /// A name that no longer resolves — a user sound since deleted — plays
    /// nothing rather than falling back to another sound: a cue the user did
    /// not choose is worse than silence.
    static func play(named name: String) {
        guard let id = soundID(for: name) else { return }
        AudioServicesPlayAlertSound(id)
    }

    /// Sound IDs are handles the system keeps alive; creating one per playback
    /// would leak them on every dictation.
    private static var soundIDs: [String: SystemSoundID] = [:]

    private static func soundID(for name: String) -> SystemSoundID? {
        if let cached = soundIDs[name] { return cached }
        guard let url = soundURL(named: name, in: soundSearchPaths) else { return nil }

        var id: SystemSoundID = 0
        guard AudioServicesCreateSystemSoundID(url as CFURL, &id) == kAudioServicesNoError else { return nil }

        soundIDs[name] = id
        return id
    }
}
