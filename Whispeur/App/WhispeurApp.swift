// WhispeurApp.swift
// Whispeur

import SwiftUI
import AVFoundation

@main
struct WhispeurApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Services

    let hotkeyManager    = HotkeyManager()
    let audioCapture     = AudioCaptureService()
    let whisperService   = WhisperService()
    let clipboardService = ClipboardService()
    let settings         = AppSettings.shared

    private(set) var coordinator: RecordingCoordinator!
    private var statusBar: StatusBarController!

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {

        // 1. Build the coordinator.
        coordinator = RecordingCoordinator(
            hotkeyManager: hotkeyManager,
            audioCapture: audioCapture,
            whisperService: whisperService,
            clipboardService: clipboardService
        )

        // 2. Apply stored settings to services.
        applySettings()

        // 3. Status bar.
        statusBar = StatusBarController(coordinator: coordinator, settings: settings)

        // 4. Observe pipeline state → update icon (zero-latency via withObservationTracking).
        observePipelineState()

        // 5. Microphone permission (non-blocking).
        Task { @MainActor in
            let micPermission = MicrophonePermissionManager()
            await micPermission.requestIfNeeded()
        }

        // 6. Start global hotkey listener.
        hotkeyManager.startListening()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager.stopListening()
    }

    // MARK: - Settings → Services sync

    private func applySettings() {
        hotkeyManager.updateHotKey(settings.currentHotKey)
        hotkeyManager.setMode(settings.hotKeyMode)
        coordinator.modelURL = settings.selectedModelURL
        coordinator.language = settings.selectedLanguage
        clipboardService.autoPasteEnabled = settings.autoPasteEnabled
    }

    /// Reactive observation: called whenever pipelineState changes.
    private func observePipelineState() {
        withObservationTracking {
            let state = coordinator.pipelineState
            statusBar.updateIcon(for: state)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.observePipelineState()
            }
        }
    }
}
