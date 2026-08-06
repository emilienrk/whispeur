// SystemSoundLibraryTests.swift
// WhispeurTests

import Testing
import Foundation

/// Real directories rather than a mocked FileManager: the logic being tested is
/// precedence between directories, which only means something on a real one.
private final class SoundFixture {
    let root: URL
    let system: URL
    let user: URL

    init() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sounds-\(UUID().uuidString)")
        system = root.appendingPathComponent("System")
        user = root.appendingPathComponent("User")
        for dir in [system, user] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    func write(_ fileName: String, in directory: URL) throws {
        try Data().write(to: directory.appendingPathComponent(fileName))
    }

    /// Least specific first, as the real search paths are ordered.
    var paths: [String] { [system.path, user.path] }

    deinit { try? FileManager.default.removeItem(at: root) }
}

@Suite("SystemSoundLibrary")
struct SystemSoundLibraryTests {

    @Test("Names drop the extension and come back in system-list order")
    func namesAreSortedAndStripped() throws {
        let fixture = try SoundFixture()
        try fixture.write("Tink.aiff", in: fixture.system)
        try fixture.write("Basso.aiff", in: fixture.system)
        try fixture.write("Glass.aiff", in: fixture.system)

        #expect(soundNames(in: fixture.paths) == ["Basso", "Glass", "Tink"])
    }

    @Test("A user sound shadows a system one of the same name instead of duplicating it")
    func userSoundShadowsSystemSound() throws {
        let fixture = try SoundFixture()
        try fixture.write("Tink.aiff", in: fixture.system)
        try fixture.write("Tink.aiff", in: fixture.user)

        #expect(soundNames(in: fixture.paths) == ["Tink"])
        #expect(soundURL(named: "Tink", in: fixture.paths)?.path == fixture.user.appendingPathComponent("Tink.aiff").path)
    }

    @Test("Non-audio files are ignored")
    func nonAudioFilesAreIgnored() throws {
        let fixture = try SoundFixture()
        try fixture.write("Tink.aiff", in: fixture.system)
        try fixture.write(".DS_Store", in: fixture.system)
        try fixture.write("readme.txt", in: fixture.system)

        #expect(soundNames(in: fixture.paths) == ["Tink"])
    }

    @Test("A user sound in any accepted format is listed")
    func userFormatsAreAccepted() throws {
        let fixture = try SoundFixture()
        try fixture.write("Chime.wav", in: fixture.user)
        try fixture.write("Bell.m4a", in: fixture.user)

        #expect(soundNames(in: fixture.paths) == ["Bell", "Chime"])
    }

    @Test("A missing directory is skipped, not an error")
    func missingDirectoryIsSkipped() throws {
        // /Library/Sounds and ~/Library/Sounds do not exist on a fresh system.
        let fixture = try SoundFixture()
        try fixture.write("Tink.aiff", in: fixture.system)

        #expect(soundNames(in: fixture.paths + ["/nowhere/at/all"]) == ["Tink"])
    }

    @Test("An unknown name resolves to nothing rather than another sound")
    func unknownNameResolvesToNil() throws {
        let fixture = try SoundFixture()
        try fixture.write("Tink.aiff", in: fixture.system)

        #expect(soundURL(named: "Deleted", in: fixture.paths) == nil)
    }

    @Test("The real system directory carries the sounds the pickers rely on")
    func realSystemSoundsAreListed() {
        // The defaults shipped in AppSettings must exist, or the cue is silent.
        let names = soundNames(in: soundSearchPaths)
        #expect(names.contains("Tink"))
        #expect(names.contains("Pop"))
    }
}
