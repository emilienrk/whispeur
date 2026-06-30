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

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Request microphone permission on launch non-blockingly.
        Task { @MainActor in
            let micPermission = MicrophonePermissionManager()
            await micPermission.requestIfNeeded()
        }
    }
}
