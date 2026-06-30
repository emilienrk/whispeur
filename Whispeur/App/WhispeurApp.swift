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
        print("[Whispeur] Lancé en background")

        // Demande la permission micro dès le lancement (non-bloquant).
        // MicrophonePermissionManager est @MainActor, donc on l'instancie dans une Task @MainActor.
        Task { @MainActor in
            let micPermission = MicrophonePermissionManager()
            await micPermission.requestIfNeeded()
            print("[Whispeur] Permission microphone : \(micPermission.status)")
        }
    }
}
