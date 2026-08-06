// AudioProcessProbe.swift
// Whispeur
//
// Reports which processes are currently feeding the audio output, so the media
// controller can tell "Spotify is playing" from "a call is running" from
// "nothing at all".
//
// The device-level kAudioDevicePropertyDeviceIsRunningSomewhere cannot make
// that distinction. It answers "is any sound coming out": true during a call,
// and false for a player that is open but paused. Acting on that answer meant
// sending the Play/Pause key during a call, where it reached whatever paused
// player was the system's now-playing app and started it.

import Foundation
import CoreAudio

struct AudioProcess: Equatable {
    let pid: pid_t
    let bundleID: String?
    /// Whether the same process is also capturing audio while it plays.
    let isCapturingInput: Bool
}

@MainActor
protocol AudioProcessProbe {
    /// Processes running an output stream right now, ours excluded.
    func outputtingProcesses() -> [AudioProcess]
}

enum AudioSourceKind {
    case communication
    case player
}

/// Communication apps must never be interrupted, so anything that looks like
/// one is left alone.
///
/// The primary signal is behavioural rather than a name: a process that plays
/// *and* records at the same time is holding a conversation, not playing music.
/// That covers apps nobody listed — a Google Meet in a browser tab included,
/// which no bundle ID could ever catch since it shares its process with YouTube.
///
/// The name list is a fallback for the case the behavioural signal misses:
/// Apple routes FaceTime audio through daemons, and the daemon that plays the
/// remote party is not necessarily the one holding the microphone.
///
/// Over-approximating here is safe. Calling a player a communication app only
/// ever makes Whispeur abstain; it can never make it act wrongly.
func classify(_ process: AudioProcess) -> AudioSourceKind {
    if process.isCapturingInput { return .communication }
    guard let bundleID = process.bundleID else { return .player }
    return communicationBundleIDs.contains(bundleID) ? .communication : .player
}

private let communicationBundleIDs: Set<String> = [
    // Verified against the bundles installed on the build machine.
    "com.apple.FaceTime",
    "com.hnc.Discord",
    "com.microsoft.teams2",
    // Observed in the process list on this machine; these daemons carry the
    // audio of FaceTime and Continuity calls rather than the app itself.
    "com.apple.avconferenced",
    "com.apple.TelephonyUtilities",
    "com.apple.callservicesd",
    // Not installed here, so these are the published identifiers rather than
    // ones read off a bundle. An identifier that turns out to be wrong simply
    // never matches, and the behavioural signal above still covers the app.
    "us.zoom.xos",
    "com.microsoft.teams",
    "com.tinyspeck.slackmacgap",
    "com.skype.skype",
    "Cisco-Systems.Spark",
]

// MARK: - Real implementation

/// Reads the per-process audio state published by the HAL. Available as public
/// API since macOS 14.4 and needs no entitlement or TCC prompt — only creating
/// a process *tap* to capture the samples would, and we never do that.
///
/// Any CoreAudio failure is reported as "not playing", keeping Whispeur passive
/// when it cannot see clearly.
struct CoreAudioProcessProbe: AudioProcessProbe {

    private let ownPID = ProcessInfo.processInfo.processIdentifier
    private let ownBundleID = Bundle.main.bundleIdentifier

    func outputtingProcesses() -> [AudioProcess] {
        processObjects().compactMap { object in
            guard readUInt32(object, kAudioProcessPropertyIsRunningOutput) == 1,
                  let pid = readPID(object),
                  // Our own confirmation sound would otherwise read as a player.
                  pid != ownPID
            else { return nil }

            let bundleID = readString(object, kAudioProcessPropertyBundleID)
            // A second copy of Whispeur — a build running next to the installed
            // app — plays the same sounds, and a PID check cannot see it. Taking
            // it for a player sends Play/Pause into a silent system, which
            // *starts* music rather than stopping it.
            guard bundleID == nil || bundleID != ownBundleID else { return nil }

            return AudioProcess(
                pid: pid,
                bundleID: bundleID,
                isCapturingInput: readUInt32(object, kAudioProcessPropertyIsRunningInput) == 1
            )
        }
    }

    private func processObjects() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let system = AudioObjectID(kAudioObjectSystemObject)

        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }

        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objects) == noErr else { return [] }
        return objects
    }

    private func readUInt32(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var address = propertyAddress(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private func readPID(_ object: AudioObjectID) -> pid_t? {
        var address = propertyAddress(kAudioProcessPropertyPID)
        var value: pid_t = -1
        var size = UInt32(MemoryLayout<pid_t>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    /// Read through a byte buffer rather than a `CFString?` inout: taking the
    /// address of an optional object reference is not a valid way to receive a
    /// +1 CFString from CoreAudio.
    private func readString(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = propertyAddress(selector)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr,
              size == UInt32(MemoryLayout<CFString>.size)
        else { return nil }

        var buffer = [UInt8](repeating: 0, count: Int(size))
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &buffer) == noErr else { return nil }

        // CoreAudio hands back a +1 reference the caller owns, so consume it
        // rather than loading it as a managed CFString, which would retain a
        // second time and leak the original.
        let unmanaged = buffer.withUnsafeBytes { $0.load(as: Unmanaged<CFString>.self) }
        return unmanaged.takeRetainedValue() as String
    }

    private func propertyAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }
}
