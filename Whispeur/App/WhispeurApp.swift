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
    let historyService   = HistoryService()
    let micPermissionManager = MicrophonePermissionManager()

    private(set) var coordinator: RecordingCoordinator!
    private var statusBar: StatusBarController!

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {

        // 1. Build the coordinator.
        coordinator = RecordingCoordinator(
            hotkeyManager: hotkeyManager,
            audioCapture: audioCapture,
            whisperService: whisperService,
            clipboardService: clipboardService,
            historyService: historyService
        )

        // 2. Apply stored settings to services.
        applySettings()

        // 3. Status bar.
        statusBar = StatusBarController(
            coordinator: coordinator,
            settings: settings,
            historyService: historyService,
            micPermissionManager: micPermissionManager
        )

        // 4. Observe pipeline state → update icon (zero-latency via withObservationTracking).
        observePipelineState()

        // 5. Microphone permission (non-blocking, status observable via micPermissionManager).
        Task { @MainActor in
            await micPermissionManager.requestIfNeeded()
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

    /// Reactive observation loop: watches every pipelineState transition.
    /// Uses withObservationTracking recursively — re-registers after each change
    /// so no transition (including back to .idle) is ever missed.
    private func observePipelineState() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self._observeNextChange()
        }
    }

    private func _observeNextChange() {
        withObservationTracking {
            // Read the state inside the tracking scope so the system registers the dependency.
            let state = coordinator.pipelineState
            statusBar.updateIcon(for: state)
        } onChange: { [weak self] in
            // onChange fires on a background thread — hop back to MainActor immediately.
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Apply the new state, then re-register for the next change.
                self.statusBar.updateIcon(for: self.coordinator.pipelineState)
                self._observeNextChange()
            }
        }
    }
}
