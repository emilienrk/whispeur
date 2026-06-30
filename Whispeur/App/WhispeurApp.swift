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

    // Observation task — keeps the status bar icon in sync with pipeline state.
    private var stateObservationTask: Task<Void, Never>?

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
        statusBar = StatusBarController(coordinator: coordinator)

        // 4. Observe pipeline state → update icon.
        stateObservationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var lastState: PipelineState = .idle
            while !Task.isCancelled {
                let current = self.coordinator.pipelineState
                if current != lastState {
                    lastState = current
                    self.statusBar.updateIcon(for: current)
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }

        // 5. Microphone permission (non-blocking).
        Task { @MainActor in
            let micPermission = MicrophonePermissionManager()
            await micPermission.requestIfNeeded()
        }

        // 6. Start global hotkey listener.
        hotkeyManager.startListening()
    }

    func applicationWillTerminate(_ notification: Notification) {
        stateObservationTask?.cancel()
        hotkeyManager.stopListening()
    }

    // MARK: - Settings → Services sync

    private func applySettings() {
        // Hotkey
        hotkeyManager.updateHotKey(settings.currentHotKey)
        hotkeyManager.setMode(settings.hotKeyMode)

        // Model
        coordinator.modelURL = settings.selectedModelURL
        coordinator.language = settings.selectedLanguage

        // Clipboard
        clipboardService.autoPasteEnabled = settings.autoPasteEnabled
    }
}
