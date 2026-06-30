// StatusBarController.swift
// Whispeur
//
// Manages the NSStatusItem (menu bar icon) and its rich menu.
// Left click shows the menu directly (with "Start recording" action).
// The icon reacts live to the PipelineState via observation.

import AppKit
import SwiftUI

@MainActor
final class StatusBarController {

    // MARK: - Properties

    private var statusItem: NSStatusItem
    private var settingsWindow: NSWindow?
    private let coordinator: RecordingCoordinator
    private let settings: AppSettings

    // Animation timer for the recording pulse.
    private var pulseTimer: Timer?
    private var pulsePhase: Bool = false

    // Strong reference to the window delegate to prevent premature deallocation
    // (NSWindow.delegate is weak, so we must retain it ourselves).
    private var windowCloseDelegate: WindowCloseDelegate?

    // MARK: - Init

    init(coordinator: RecordingCoordinator, settings: AppSettings = .shared) {
        self.coordinator = coordinator
        self.settings = settings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        configureButton()
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

    // MARK: - Menu construction (rebuilt on each show so it's always fresh)

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        // ── Status / trigger ─────────────────────────────────────────────
        let isRecording = coordinator.pipelineState == .recording
        let isIdle = coordinator.pipelineState == .idle

        let triggerItem = NSMenuItem(
            title: isRecording ? "⏹ Arrêter l'enregistrement" : "▶ Démarrer l'enregistrement",
            action: isIdle || isRecording ? #selector(triggerRecording) : nil,
            keyEquivalent: ""
        )
        triggerItem.target = self
        triggerItem.isEnabled = isIdle || isRecording
        menu.addItem(triggerItem)

        menu.addItem(.separator())

        // ── Current config (informational, disabled) ──────────────────────
        let hotKeyItem = NSMenuItem(
            title: "Raccourci : \(settings.currentHotKey.displayString)  ·  \(settings.hotKeyMode.displayName)",
            action: nil,
            keyEquivalent: ""
        )
        hotKeyItem.isEnabled = false
        hotKeyItem.attributedTitle = NSAttributedString(
            string: hotKeyItem.title,
            attributes: [.foregroundColor: NSColor.secondaryLabelColor, .font: NSFont.systemFont(ofSize: 11)]
        )
        menu.addItem(hotKeyItem)

        let modelName = settings.selectedModelDescriptor?.name ?? "Aucun modèle"
        let modelItem = NSMenuItem(
            title: "Modèle : \(modelName)",
            action: nil,
            keyEquivalent: ""
        )
        modelItem.isEnabled = false
        modelItem.attributedTitle = NSAttributedString(
            string: modelItem.title,
            attributes: [.foregroundColor: NSColor.secondaryLabelColor, .font: NSFont.systemFont(ofSize: 11)]
        )
        menu.addItem(modelItem)

        // ── Favorite models ───────────────────────────────────────────────
        let favorites = settings.favoritedModelDescriptors.filter { $0.isDownloaded }
        if !favorites.isEmpty {
            menu.addItem(.separator())

            let favHeader = NSMenuItem(title: "Modèles favoris", action: nil, keyEquivalent: "")
            favHeader.isEnabled = false
            favHeader.attributedTitle = NSAttributedString(
                string: favHeader.title,
                attributes: [
                    .foregroundColor: NSColor.tertiaryLabelColor,
                    .font: NSFont.systemFont(ofSize: 10, weight: .medium)
                ]
            )
            menu.addItem(favHeader)

            for model in favorites {
                let isActive = settings.selectedModelFilename == model.filename
                let item = NSMenuItem(
                    title: (isActive ? "✓ " : "   ") + model.name + "  ·  \(model.sizeInfo)",
                    action: #selector(selectFavoriteModel(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = model.filename
                if isActive {
                    item.state = .on
                }
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        // ── Settings / Quit ───────────────────────────────────────────────
        let settingsItem = NSMenuItem(title: "Paramètres…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem(title: "Quitter Whispeur", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        return menu
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
            button.image = NSImage(systemSymbolName: "waveform.circle", accessibilityDescription: "Chargement…")
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
            MainActor.assumeIsolated {
                guard let self, let button = self.statusItem.button else { return }
                self.pulsePhase.toggle()
                button.contentTintColor = self.pulsePhase ? .systemRed : .systemRed.withAlphaComponent(0.4)
            }
        }
    }

    // MARK: - Actions

    @objc private func handleButtonClick(_ sender: NSStatusBarButton) {
        // Both left and right click show the rich menu.
        let menu = buildMenu()
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        // Clear the menu reference so the next click rebuilds it fresh.
        DispatchQueue.main.async { [weak self] in
            self?.statusItem.menu = nil
        }
    }

    @objc private func triggerRecording() {
        switch coordinator.pipelineState {
        case .idle:
            coordinator.onHotkeyDown()
        case .recording:
            coordinator.onHotkeyUp()
        default:
            break
        }
    }

    @objc private func selectFavoriteModel(_ sender: NSMenuItem) {
        guard let filename = sender.representedObject as? String,
              let descriptor = WhisperModelDescriptor.catalog.first(where: { $0.filename == filename })
        else { return }
        settings.selectedModelFilename = filename
        coordinator.modelURL = descriptor.localURL
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
        window.title = "Whispeur"
        // Transparent titlebar — the SwiftUI header acts as the title.
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.setContentSize(NSSize(width: 520, height: 540))
        window.center()
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        let closeDelegate = WindowCloseDelegate { [weak self] in
            self?.settingsWindow = nil
            self?.windowCloseDelegate = nil
        }
        windowCloseDelegate = closeDelegate
        window.delegate = closeDelegate
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
