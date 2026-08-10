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
    let mediaPlayback = MediaPlaybackController(
        probe: CoreAudioProcessProbe(),
        keySender: SystemMediaKeySender(),
        isEnabled: { AppSettings.shared.pauseMediaWhileRecording }
    )

    private(set) lazy var coordinator: RecordingCoordinator = {
        RecordingCoordinator(
            hotkeyManager: hotkeyManager,
            audioCapture: audioCapture,
            whisperService: whisperService,
            clipboardService: clipboardService,
            historyService: historyService,
            mediaPlayback: mediaPlayback
        )
    }()
}

// MARK: - AppDelegate

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {

    let servicesContainer = ServicesContainer()

    private var statusBar: StatusBarController!
    private var iconTask: Task<Void, Never>?

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

        // The onboarding asks for the microphone itself, with an explanation
        // shown first — prompting here would fire the system dialog cold.
        if sc.settings.hasCompletedOnboarding {
            Task { @MainActor in
                await sc.micPermManager.requestIfNeeded()
            }
        } else {
            OnboardingWindowController.shared.show(services: sc)
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

    /// Watches every pipelineState transition. `Observations` hands them over as
    /// an async sequence — no tracking to re-arm by hand after each change.
    private func observePipelineState() {
        iconTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let coordinator = self.servicesContainer.coordinator
            for await state in Observations({ coordinator.pipelineState }) {
                self.statusBar.updateIcon(for: state)
            }
        }
    }
}
