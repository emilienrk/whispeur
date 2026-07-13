// WhispeurApp.swift
// Whispeur

import SwiftUI
import AVFoundation

@main
struct WhispeurApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // macOS 14+ LSUIElement apps don't handle the Settings scene well without a main menu.
        // We use a custom NSWindow to show settings.
        // But an App must have at least one scene.
        Settings {
            EmptyView()
        }
    }
}

// MARK: - Services container

/// Bundles all long-lived services so the native Settings scene can reach them.
@MainActor
final class ServicesContainer: ObservableObject {
    let settings         = AppSettings.shared
    let historyService   = HistoryService()
    let micPermManager   = MicrophonePermissionManager()
    let hotkeyManager    = HotkeyManager()
    let audioCapture     = AudioCaptureService()
    let whisperService   = WhisperService()
    let clipboardService = ClipboardService()

    private(set) lazy var coordinator: RecordingCoordinator = {
        RecordingCoordinator(
            hotkeyManager: hotkeyManager,
            audioCapture: audioCapture,
            whisperService: whisperService,
            clipboardService: clipboardService,
            historyService: historyService
        )
    }()
}

// MARK: - AppDelegate

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {

    let servicesContainer = ServicesContainer()

    private var statusBar: StatusBarController!

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        let sc = servicesContainer

        // Apply stored settings to services.
        applySettings(sc)

        // Build the status bar controller.
        statusBar = StatusBarController(
            coordinator: sc.coordinator,
            settings: sc.settings,
            historyService: sc.historyService,
            micPermissionManager: sc.micPermManager,
            servicesContainer: sc
        )

        // Observe pipeline state → update icon.
        observePipelineState()

        // Microphone permission (non-blocking).
        Task { @MainActor in
            await sc.micPermManager.requestIfNeeded()
        }

        // Start global hotkey listener.
        sc.hotkeyManager.startListening()

        // Démarre Sparkle (checks automatiques + manuels).
        UpdaterService.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        servicesContainer.hotkeyManager.stopListening()
    }

    // MARK: - Settings → Services sync

    private func applySettings(_ sc: ServicesContainer) {
        let s = sc.settings
        sc.hotkeyManager.updateHotKey(s.currentHotKey)
        sc.hotkeyManager.setMode(s.hotKeyMode)
        sc.coordinator.modelURL = s.selectedModelURL
        sc.coordinator.language = s.selectedLanguage
        sc.clipboardService.autoPasteEnabled = s.autoPasteEnabled
    }

    // MARK: - Observation loop

    /// Reactive observation loop: watches every pipelineState transition.
    private func observePipelineState() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self._observeNextChange()
        }
    }

    private func _observeNextChange() {
        withObservationTracking {
            let state = servicesContainer.coordinator.pipelineState
            statusBar.updateIcon(for: state)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.statusBar.updateIcon(for: self.servicesContainer.coordinator.pipelineState)
                self._observeNextChange()
            }
        }
    }
}
