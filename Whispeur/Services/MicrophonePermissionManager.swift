// MicrophonePermissionManager.swift
// Whispeur
//
// Manages macOS microphone access permissions.

import AVFoundation
import AppKit
import Foundation
import os

private let logger = Logger(subsystem: "com.whispeur", category: "MicPermission")

enum MicrophonePermissionStatus: Equatable {
    case undetermined
    case granted
    case denied
    case restricted
}

/// Handles microphone permissions and exposes an observable status.
@MainActor
@Observable
final class MicrophonePermissionManager {

    private(set) var status: MicrophonePermissionStatus = .undetermined

    init() {
        status = Self.currentStatus()
    }

    /// Prompts the user for microphone access if undetermined.
    func requestIfNeeded() async {
        let current = Self.currentStatus()
        if current != .undetermined {
            status = current
            return
        }

        let granted = await AVAudioApplication.requestRecordPermission()
        status = granted ? .granted : .denied
    }

    /// Opens System Settings to the Microphone Privacy pane.
    func openSystemPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    var canRecord: Bool { status == .granted }

    static func currentStatus() -> MicrophonePermissionStatus {
        switch AVAudioApplication.shared.recordPermission {
        case .undetermined: return .undetermined
        case .granted:      return .granted
        case .denied:       return .denied
        @unknown default:   return .restricted
        }
    }
}
