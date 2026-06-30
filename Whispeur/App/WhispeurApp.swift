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

    // MARK: - Services (kept alive for the lifetime of the app)

    let hotkeyManager   = HotkeyManager()
    let audioCapture    = AudioCaptureService()
    let whisperService  = WhisperService()
    let clipboardService = ClipboardService()

    /// Central pipeline coordinator.
    private(set) var coordinator: RecordingCoordinator!

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. Wire the coordinator.
        coordinator = RecordingCoordinator(
            hotkeyManager: hotkeyManager,
            audioCapture: audioCapture,
            whisperService: whisperService,
            clipboardService: clipboardService
        )

        // 2. Set the default model URL (dev path — will be replaced by ModelManager later).
        coordinator.modelURL = WhisperService.devModelURL()

        // 3. Request microphone permission (non-blocking).
        Task { @MainActor in
            let micPermission = MicrophonePermissionManager()
            await micPermission.requestIfNeeded()
        }

        // 4. Start the global hotkey listener if Accessibility is already granted.
        //    If not, the user will be guided through Settings.
        hotkeyManager.startListening()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager.stopListening()
    }
}

