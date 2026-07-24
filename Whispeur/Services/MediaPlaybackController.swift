// MediaPlaybackController.swift
// Whispeur
//
// Pauses whatever is playing while a dictation runs, then resumes it.
//
// The Play/Pause media key is a blind toggle: nothing tells us whether a player
// actually received it. So we only send Play once we have proof the sound
// stopped — otherwise ending a Zoom call would start Spotify out of nowhere.
//
// Both CoreAudio readings happen while the microphone is closed (before capture
// starts, and after it stops). On AirPods or any device that is both input and
// output, a reading taken during capture would always report "running" because
// of our own microphone, and the music would never resume.

import Foundation
import AppKit
import CoreAudio

// MARK: - Injected dependencies

@MainActor
protocol SystemAudioProbe {
    /// Whether the default output device is currently performing I/O.
    var isOutputActive: Bool { get }
}

@MainActor
protocol MediaKeySender {
    func sendPlayPause()
}

// MARK: - Controller

@MainActor
final class MediaPlaybackController {

    private let probe: SystemAudioProbe
    private let keySender: MediaKeySender
    private let isEnabled: @MainActor () -> Bool
    private let resumePollInterval: Duration
    private let resumeTimeout: Duration

    /// True while a player is paused *by us* and is owed a resume.
    private(set) var didPause = false
    /// Bumped by every pause. A resume that was still settling when the next
    /// dictation began belongs to the previous one and must stay silent.
    private var generation = 0
    /// True between the start of a resume and the end of its settle delay.
    private var resumePending = false

    init(
        probe: SystemAudioProbe,
        keySender: MediaKeySender,
        isEnabled: @escaping @MainActor () -> Bool,
        resumePollInterval: Duration = .milliseconds(50),
        resumeTimeout: Duration = .seconds(1)
    ) {
        self.probe = probe
        self.keySender = keySender
        self.isEnabled = isEnabled
        self.resumePollInterval = resumePollInterval
        self.resumeTimeout = resumeTimeout
    }

    /// Call before opening the microphone, so the probe reading is not polluted
    /// by our own capture device.
    func pauseForRecording() {
        generation &+= 1

        // A resume may still be settling, or we may already hold a resume debt
        // from an earlier dictation. Either way the media is paused by us, and
        // the Play/Pause key would start it rather than stop it.
        if resumePending || didPause {
            resumePending = false
            didPause = true
            return
        }

        guard isEnabled(), probe.isOutputActive else {
            didPause = false
            return
        }
        keySender.sendPlayPause()
        didPause = true
    }

    /// Safe to call from every pipeline exit path — errors included. The
    /// `didPause` guard makes repeated calls no-ops.
    func resumeAfterRecording() async {
        guard didPause else { return }
        didPause = false
        resumePending = true
        let generationAtResume = generation

        // A single reading is a coin flip: closing the mic can restart a shared
        // input/output device (AirPods switching Bluetooth profile), and a player
        // needs a moment to release its IOProc. Poll until the output really goes
        // quiet, and only then claim the pause worked.
        let deadline = ContinuousClock.now + resumeTimeout
        while ContinuousClock.now < deadline {
            try? await Task.sleep(for: resumePollInterval)

            // A new dictation took ownership of the media state while we polled.
            guard generationAtResume == generation else { return }

            if !probe.isOutputActive {
                resumePending = false
                keySender.sendPlayPause()
                return
            }
        }

        // Still noisy: nobody obeyed our pause, or another source is talking over
        // it. Sending Play would start something the user never asked for, so keep
        // the debt for a later dictation to settle.
        resumePending = false
        didPause = true
    }
}

// MARK: - Real implementations

/// Reports whether the default output device is performing I/O.
/// Any CoreAudio failure is reported as "silent" so Whispeur stays passive.
struct CoreAudioOutputProbe: SystemAudioProbe {

    var isOutputActive: Bool {
        guard let device = defaultOutputDevice() else { return false }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var isRunning: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &isRunning)

        guard status == noErr else { return false }
        return isRunning != 0
    }

    private func defaultOutputDevice() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        )

        guard status == noErr, deviceID != AudioObjectID(kAudioObjectUnknown) else { return nil }
        return deviceID
    }
}

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
