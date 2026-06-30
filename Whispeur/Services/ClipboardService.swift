// ClipboardService.swift
// Whispeur
//
// Writes transcribed text to the clipboard and optionally simulates Cmd+V
// using CGEvent (requires Accessibility permission).
// Falls back to a macOS notification when paste is not possible.

import AppKit
import ApplicationServices
import UserNotifications

// MARK: - Paste Result

enum PasteResult {
    /// Text was both copied and pasted into the active app.
    case pasted
    /// Text was copied only (Accessibility unavailable or paste failed).
    case copiedOnly
}

// MARK: - ClipboardService

/// Copies text to the general pasteboard and optionally auto-pastes it.
@MainActor
final class ClipboardService {

    // MARK: - Properties

    /// When `true`, the service will attempt to simulate Cmd+V after copying.
    var autoPasteEnabled: Bool = true

    // MARK: - Public API

    /// Main entry point: copies `text` then pastes if `autoPasteEnabled`.
    ///
    /// - Returns: `.pasted` if the full paste succeeded, `.copiedOnly` otherwise.
    @discardableResult
    func copyAndPaste(_ text: String) async -> PasteResult {
        // 1. Write to the pasteboard.
        copyToClipboard(text)

        // 2. Attempt auto-paste if requested.
        if autoPasteEnabled && AXIsProcessTrusted() {
            let success = await simulatePaste()
            if success {
                return .pasted
            }
        }

        // 3. Fallback: notify user.
        if autoPasteEnabled {
            await sendCopiedNotification()
        }
        return .copiedOnly
    }

    /// Writes text to the general pasteboard (does NOT paste).
    func copyToClipboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    // MARK: - Accessibility check

    /// Whether the process has Accessibility permission (required for auto-paste).
    var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    // MARK: - Private implementation

    /// Simulates ⌘V by posting keyDown + keyUp CGEvents to the HID event source.
    /// Must be called after the text is already in the pasteboard.
    ///
    /// - Returns: `true` if events were posted without error.
    private func simulatePaste() async -> Bool {
        // Small delay: let the system register the key release before injecting Cmd+V.
        // Without this, some apps (e.g. Terminal) might not receive the paste.
        try? await Task.sleep(for: .milliseconds(80))

        return await Task.detached(priority: .userInitiated) {
            guard let source = CGEventSource(stateID: .hidSystemState) else { return false }

            let vKeyCode: CGKeyCode = 9 // kVK_ANSI_V

            guard
                let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
                let keyUp   = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
            else { return false }

            // Add ⌘ flag.
            keyDown.flags = .maskCommand
            keyUp.flags   = .maskCommand

            // Post to the HID event stream (affects the currently focused application).
            keyDown.post(tap: .cgSessionEventTap)
            keyUp.post(tap: .cgSessionEventTap)

            return true
        }.value
    }

    /// Sends a local notification informing the user the text is in the clipboard.
    private func sendCopiedNotification() async {
        let center = UNUserNotificationCenter.current()

        // Request notification authorization if not yet determined.
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
        guard settings.authorizationStatus == .authorized ||
              settings.authorizationStatus == .notDetermined else { return }

        let content = UNMutableNotificationContent()
        content.title = "Texte copié dans le presse-papier"
        content.body  = "Aucun champ de texte actif détecté. Collez avec ⌘V."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "com.whispeur.copied-\(UUID().uuidString)",
            content: content,
            trigger: nil // deliver immediately
        )
        try? await center.add(request)
    }
}
