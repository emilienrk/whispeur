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

    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    // MARK: - Public API

    /// Main entry point: copies `text` then pastes if `autoPasteEnabled`.
    ///
    /// - Returns: `.pasted` if the full paste succeeded, `.copiedOnly` otherwise.
    @discardableResult
    func copyAndPaste(_ text: String) async -> PasteResult {
        // Pasting only borrows the pasteboard — whatever the user had copied is
        // handed back once the target app has read the transcription.
        let previousItems = snapshotPasteboard()

        // 1. Write to the pasteboard.
        let changeCount = copyToClipboard(text)

        // 2. Attempt auto-paste if requested.
        if autoPasteEnabled && AXIsProcessTrusted() {
            let success = await simulatePaste()
            if success {
                // The target app reads the pasteboard on its own run loop; restoring
                // too early makes it paste the previous content instead.
                try? await Task.sleep(for: .milliseconds(300))
                restorePasteboard(previousItems, ifUnchangedSince: changeCount)
                return .pasted
            }
        }

        // 3. Fallback: notify user. The text stays on the pasteboard — that is the
        // whole point of the fallback, so nothing is restored here.
        if autoPasteEnabled {
            await sendCopiedNotification()
        }
        return .copiedOnly
    }

    /// Writes text to the pasteboard (does NOT paste).
    ///
    /// - Returns: the resulting `changeCount`, to detect later writes by other apps.
    @discardableResult
    func copyToClipboard(_ text: String) -> Int {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        return pasteboard.changeCount
    }

    // MARK: - Pasteboard save & restore

    /// Detached copy of the current contents — the originals are invalidated by
    /// the next `clearContents()`, so every type has to be copied out eagerly.
    func snapshotPasteboard() -> [NSPasteboardItem] {
        guard let items = pasteboard.pasteboardItems else { return [] }
        return items.compactMap { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy.types.isEmpty ? nil : copy
        }
    }

    /// Puts `items` back, unless another app wrote to the pasteboard meanwhile —
    /// restoring then would silently destroy what the user just copied.
    func restorePasteboard(_ items: [NSPasteboardItem], ifUnchangedSince changeCount: Int) {
        guard pasteboard.changeCount == changeCount else { return }
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        pasteboard.writeObjects(items)
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

        // CGEvent.post must NOT run on the AVFoundation realtime thread (RealtimeMessenger).
        // We use DispatchQueue.main to guarantee a safe, deterministic posting thread.
        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                guard let source = CGEventSource(stateID: .hidSystemState) else {
                    continuation.resume(returning: false)
                    return
                }

                let vKeyCode: CGKeyCode = 9 // kVK_ANSI_V

                guard
                    let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
                    let keyUp   = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
                else {
                    continuation.resume(returning: false)
                    return
                }

                keyDown.flags = .maskCommand
                keyUp.flags   = .maskCommand

                keyDown.post(tap: .cgSessionEventTap)
                keyUp.post(tap: .cgSessionEventTap)

                continuation.resume(returning: true)
            }
        }
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
