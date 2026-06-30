// StatusBarController.swift
// Whispeur
//
// Manages the NSStatusItem (menu bar icon) and its popover/menu.
// The icon reacts live to the PipelineState via observation.

import AppKit
import SwiftUI

@MainActor
final class StatusBarController {

    // MARK: - Properties

    private var statusItem: NSStatusItem
    private var settingsWindow: NSWindow?
    private let coordinator: RecordingCoordinator

    // Animation timer for the recording pulse.
    private var pulseTimer: Timer?
    private var pulsePhase: Bool = false

    // MARK: - Init

    init(coordinator: RecordingCoordinator) {
        self.coordinator = coordinator
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        configureButton()
        configureMenu()
    }

    // MARK: - Button setup

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "Whispeur")
        button.image?.isTemplate = true
        button.action = #selector(handleButtonClick(_:))
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func configureMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Paramètres…", action: #selector(openSettings), keyEquivalent: ",")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quitter Whispeur", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = nil  // We handle left vs right click ourselves.
        statusItem.menu = menu
    }

    // MARK: - State updates (call from coordinator observation)

    func updateIcon(for state: PipelineState) {
        pulseTimer?.invalidate()
        pulseTimer = nil
        guard let button = statusItem.button else { return }

        switch state {
        case .idle:
            button.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "Whispeur")
            button.image?.isTemplate = true
            button.contentTintColor = nil

        case .loadingModel:
            button.image = NSImage(systemSymbolName: "mic.badge.ellipsis", accessibilityDescription: "Chargement…")
            button.image?.isTemplate = false
            button.contentTintColor = .systemOrange

        case .recording:
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Enregistrement…")
            button.image?.isTemplate = false
            button.contentTintColor = .systemRed
            startPulse()

        case .transcribing:
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Transcription…")
            button.image?.isTemplate = false
            button.contentTintColor = .systemBlue

        case .pasting:
            button.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Collage…")
            button.image?.isTemplate = false
            button.contentTintColor = .systemGreen

        case .error:
            button.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Erreur")
            button.image?.isTemplate = false
            button.contentTintColor = .systemOrange
        }
    }

    // MARK: - Pulse animation (recording state)

    private func startPulse() {
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            guard let self, let button = self.statusItem.button else { return }
            self.pulsePhase.toggle()
            button.contentTintColor = self.pulsePhase ? .systemRed : .systemRed.withAlphaComponent(0.4)
        }
    }

    // MARK: - Actions

    @objc private func handleButtonClick(_ sender: NSStatusBarButton) {
        // Right-click: show menu. Left-click: open settings.
        if let event = NSApp.currentEvent, event.type == .rightMouseUp {
            statusItem.menu?.popUp(
                positioning: nil,
                at: NSPoint(x: 0, y: sender.bounds.maxY + 5),
                in: sender
            )
        } else {
            openSettings()
        }
    }

    @objc func openSettings() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settings = AppSettings.shared
        let view = SettingsView(settings: settings, coordinator: coordinator)
        let hosting = NSHostingController(rootView: view)

        let window = NSWindow(contentViewController: hosting)
        window.title = "Whispeur — Paramètres"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.setContentSize(NSSize(width: 520, height: 480))
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = WindowCloseDelegate { [weak self] in
            self?.settingsWindow = nil
        }
        settingsWindow = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Helper delegate

private final class WindowCloseDelegate: NSObject, NSWindowDelegate {
    private let onClose: () -> Void
    init(_ onClose: @escaping () -> Void) { self.onClose = onClose }
    func windowWillClose(_ notification: Notification) { onClose() }
}
