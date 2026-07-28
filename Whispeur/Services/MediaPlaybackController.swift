// MediaPlaybackController.swift
// Whispeur
//
// Pauses whatever is playing while a dictation runs, then resumes it.
//
// Two rules decide everything here:
//
// 1. Whispeur only acts when it can see a player actually feeding the output.
//    A player that is open but paused feeds nothing, so it is invisible, so it
//    is left alone — it must never be woken up by a dictation.
// 2. A call in progress means hands off entirely, music included. Interrupting
//    a conversation is worse than leaving a track running for a few seconds.
//
// The Play/Pause media key is a blind toggle routed to the system's now-playing
// app, which is not necessarily the process we saw playing. Seeing audio
// per process makes that toggle checkable: if the key woke a player instead of
// pausing one, a process that was silent is suddenly playing, and we undo it.

import Foundation
import AppKit

@MainActor
protocol MediaKeySender {
    func sendPlayPause()
}

// MARK: - Controller

@MainActor
final class MediaPlaybackController {

    private let probe: AudioProcessProbe
    private let keySender: MediaKeySender
    private let isEnabled: @MainActor () -> Bool
    private let verifyDelay: Duration

    /// True while a player is paused *by us* and is owed a resume.
    private(set) var didPause = false
    private var verification: Task<Void, Never>?

    /// `verifyDelay` covers the gap between the media key landing and the woken
    /// player showing up as playing. Measured at 74-84 ms on this hardware, for
    /// a process that had to be launched first; 400 ms is five times that.
    init(
        probe: AudioProcessProbe,
        keySender: MediaKeySender,
        isEnabled: @escaping @MainActor () -> Bool,
        verifyDelay: Duration = .milliseconds(400)
    ) {
        self.probe = probe
        self.keySender = keySender
        self.isEnabled = isEnabled
        self.verifyDelay = verifyDelay
    }

    /// Returns as soon as the key is sent — the check runs on its own, so
    /// nothing is added to the delay before the microphone opens.
    func pauseForRecording() {
        verification?.cancel()
        verification = nil

        // Already paused by us and never resumed. The key would start playback
        // rather than stop it, so keep the debt for the resume that follows.
        guard !didPause, isEnabled() else { return }

        let playing = probe.outputtingProcesses()
        guard !playing.isEmpty,
              !playing.contains(where: { classify($0) == .communication })
        else { return }

        let playingBefore = Set(playing.map(\.pid))
        keySender.sendPlayPause()
        didPause = true

        let delay = verifyDelay
        verification = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }

            // A process that was silent before the key is playing now: the
            // toggle reached a paused player instead of the one we saw. Undo it
            // and drop the debt, so the resume stays silent too.
            let playingNow = Set(self.probe.outputtingProcesses().map(\.pid))
            if !playingNow.subtracting(playingBefore).isEmpty {
                self.keySender.sendPlayPause()
                self.didPause = false
            }
        }
    }

    /// Safe to call from every pipeline exit path — errors included. The
    /// `didPause` guard makes repeated calls no-ops.
    ///
    /// Deliberately not conditioned on the paused player having gone quiet:
    /// players keep their audio unit alive for seconds after a pause, so
    /// demanding proof of silence would strand the music paused.
    func resumeAfterRecording() async {
        if let verification { await verification.value }
        verification = nil

        guard didPause else { return }
        didPause = false
        keySender.sendPlayPause()
    }
}

// MARK: - Real implementation

/// Posts the system Play/Pause media key. Relies on the Accessibility
/// permission the app already holds, so no new prompt is needed — posting a
/// media key still requires it even though this goes through the HID event
/// tap rather than the session tap ClipboardService uses.
struct SystemMediaKeySender: MediaKeySender {

    /// NX_KEYTYPE_PLAY from IOKit's hidsystem/ev_keymap.h.
    private static let playPauseKey: Int32 = 16

    func sendPlayPause() {
        post(keyDown: true)
        post(keyDown: false)
    }

    private func post(keyDown: Bool) {
        let state: Int32 = keyDown ? 0xA : 0xB
        let data1 = Int((Self.playPauseKey << 16) | (state << 8))
        let flags = NSEvent.ModifierFlags(rawValue: keyDown ? 0xA00 : 0xB00)

        guard let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: data1,
            data2: -1
        ) else { return }

        event.cgEvent?.post(tap: .cghidEventTap)
    }
}
