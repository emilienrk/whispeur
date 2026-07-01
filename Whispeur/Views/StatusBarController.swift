// StatusBarController.swift
// Whispeur
//
// Manages the NSStatusItem (menu bar icon) and its rich menu.
// Menu is rebuilt via NSMenuDelegate.menuWillOpen each time it opens —
// avoids any click-handler re-entrancy that caused the duplicate icon.
// The icon reacts live to the PipelineState via observation.

import AppKit
import SwiftUI

@MainActor
final class StatusBarController: NSObject {

    // MARK: - Properties

    private var statusItem: NSStatusItem
    private var settingsWindow: NSWindow?
    private var historyWindow: NSWindow?
    private let coordinator: RecordingCoordinator
    private let settings: AppSettings
    private let historyService: HistoryService

    // The persistent NSMenu assigned once — content rebuilt in menuWillOpen.
    private let persistentMenu = NSMenu()

    // Animation timer for the recording pulse.
    private var pulseTimer: Timer?
    private var pulsePhase: Bool = false

    // Strong reference to the window delegate to prevent premature deallocation
    // (NSWindow.delegate is weak, so we must retain it ourselves).
    private var windowCloseDelegate: WindowCloseDelegate?

    // MARK: - Init

    init(coordinator: RecordingCoordinator, settings: AppSettings = .shared, historyService: HistoryService) {
        self.coordinator = coordinator
        self.settings = settings
        self.historyService = historyService
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        configureButton()
        print("[StatusBar] Initialized ✅")
    }

    // MARK: - Button setup

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "Whispeur")
        button.image?.isTemplate = true
        // Assign a persistent menu with self as delegate.
        // macOS calls menuWillOpen before each display — no custom click handler needed.
        // This is the canonical way to avoid double-icon / re-entrancy issues.
        persistentMenu.delegate = self
        statusItem.menu = persistentMenu
    }

    // MARK: - Menu construction (called from menuWillOpen)

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        // ── Status / trigger ─────────────────────────────────────────────
        let state = coordinator.pipelineState

        let triggerTitle: String
        let triggerAction: Selector?
        switch state {
        case .idle:
            triggerTitle  = "▶ Démarrer l'enregistrement"
            triggerAction = #selector(triggerRecording)
        case .loadingModel:
            triggerTitle  = "⏹ Arrêter (chargement modèle…)"
            triggerAction = #selector(triggerRecording)
        case .recording:
            triggerTitle  = "⏹ Arrêter l'enregistrement"
            triggerAction = #selector(triggerRecording)
        case .transcribing:
            triggerTitle  = "⏳ Transcription en cours…"
            triggerAction = nil
        case .pasting:
            triggerTitle  = "📋 Collage en cours…"
            triggerAction = nil
        case .error(let msg):
            triggerTitle  = "⚠️ Erreur : \(msg)"
            triggerAction = nil
        }

        let triggerItem = NSMenuItem(title: triggerTitle, action: triggerAction, keyEquivalent: "")
        triggerItem.target = self
        triggerItem.isEnabled = triggerAction != nil
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
                    title: model.name + "  ·  \(model.sizeInfo)",
                    action: #selector(selectFavoriteModel(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = model.filename
                item.state = isActive ? .on : .off  // macOS draws the native ✓ when .on
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        // ── Settings / History / Quit ─────────────────────────────────────
        let historyItem = NSMenuItem(title: "Historique des transcriptions…", action: #selector(openHistory), keyEquivalent: "h")
        historyItem.target = self
        menu.addItem(historyItem)
        
        let settingsItem = NSMenuItem(title: "Paramètres…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem(
            title: "Quitter Whispeur",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))

        return menu
    }

    // MARK: - State updates (called from coordinator observation)

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

    @objc private func triggerRecording() {
        print("[StatusBar] triggerRecording() — state: \(coordinator.pipelineState)")
        switch coordinator.pipelineState {
        case .idle:      coordinator.onHotkeyDown()
        case .recording: coordinator.onHotkeyUp()
        default:         break
        }
    }

    @objc private func selectFavoriteModel(_ sender: NSMenuItem) {
        guard let filename = sender.representedObject as? String,
              let descriptor = WhisperModelDescriptor.catalog.first(where: { $0.filename == filename })
        else { return }
        print("[StatusBar] Selecting favorite model: \(filename)")
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

    @objc func openHistory() {
        if let window = historyWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = HistoryView(historyService: historyService)
        let hosting = NSHostingController(rootView: view)

        let window = NSWindow(contentViewController: hosting)
        window.title = "Historique"
        window.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.setContentSize(NSSize(width: 450, height: 500))
        window.center()
        window.isReleasedWhenClosed = false
        window.backgroundColor = .windowBackgroundColor
        
        let closeDelegate = WindowCloseDelegate { [weak self] in
            self?.historyWindow = nil
        }
        // Assuming we need to keep a strong reference if multiple windows are open?
        // Let's just use the same windowCloseDelegate for history, or just let it close normally.
        // Actually, we can just retain the delegate if needed, but since we use historyWindow, we can just nil it out.
        // Swift requires strong ref to NSWindowDelegate if using a custom object.
        objc_setAssociatedObject(window, "WindowCloseDelegate", closeDelegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        window.delegate = closeDelegate
        historyWindow = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - NSMenuDelegate

extension StatusBarController: NSMenuDelegate {
    /// Called by macOS just before the menu is displayed — rebuild contents fresh.
    func menuWillOpen(_ menu: NSMenu) {
        print("[StatusBar] menuWillOpen — rebuilding \(settings.favoritedModelDescriptors.filter(\.isDownloaded).count) favorites")
        let fresh = buildMenu()
        menu.removeAllItems()
        // Move items from the temp menu into the persistent menu.
        while let item = fresh.items.first {
            fresh.removeItem(item)
            menu.addItem(item)
        }
    }
}

// MARK: - Helper delegate

private final class WindowCloseDelegate: NSObject, NSWindowDelegate {
    private let onClose: () -> Void
    init(_ onClose: @escaping () -> Void) { self.onClose = onClose }
    func windowWillClose(_ notification: Notification) { onClose() }
}
