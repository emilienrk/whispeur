// StatusBarController.swift
// Whispeur
//
// Manages the NSStatusItem (menu bar icon) and its rich menu.
// Menu is rebuilt via NSMenuDelegate.menuWillOpen each time it opens —
// avoids any click-handler re-entrancy that caused the duplicate icon.
// The icon reacts live to the PipelineState via observation.

import AppKit
import SwiftUI
import os

private let logger = Logger(subsystem: "com.whispeur", category: "StatusBar")

@MainActor
final class StatusBarController: NSObject {

    // MARK: - Properties

    private var statusItem: NSStatusItem
    private var settingsWindow: NSWindow?
    private let coordinator: RecordingCoordinator
    private let settings: AppSettings
    private let historyService: HistoryService
    private let micPermissionManager: MicrophonePermissionManager

    private var spinTimer: Timer?
    private var spinAngle: CGFloat = 0
    private var baseSpinImage: NSImage?

    // The persistent NSMenu assigned once — content rebuilt in menuWillOpen.
    private let persistentMenu = NSMenu()

    // Strong references to window delegates (NSWindow.delegate is weak).
    private var settingsWindowDelegate: WindowCloseDelegate?

    // MARK: - Init

    init(coordinator: RecordingCoordinator, settings: AppSettings = .shared, historyService: HistoryService, micPermissionManager: MicrophonePermissionManager) {
        self.coordinator = coordinator
        self.settings = settings
        self.historyService = historyService
        self.micPermissionManager = micPermissionManager
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        configureButton()
        logger.info("Initialized ✅")
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
            triggerTitle  = "Démarrer l'enregistrement"
            triggerAction = #selector(triggerRecording)
        case .loadingModel:
            triggerTitle  = "Arrêter l'enregistrement"
            triggerAction = #selector(triggerRecording)
        case .recording:
            triggerTitle  = "Arrêter l'enregistrement"
            triggerAction = #selector(triggerRecording)
        case .transcribing:
            triggerTitle  = "Transcription en cours…"
            triggerAction = nil
        case .pasting:
            triggerTitle  = "Collage en cours…"
            triggerAction = nil
        case .error(let msg):
            triggerTitle  = "Erreur : \(msg)"
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
            action: #selector(openSettingsToHotkey),
            keyEquivalent: ""
        )
        hotKeyItem.target = self
        hotKeyItem.isEnabled = true
        // Enlève le texte grisé pour montrer qu'il est cliquable.
        // hotKeyItem.attributedTitle = NSAttributedString(...)
        menu.addItem(hotKeyItem)

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
                let item = NSMenuItem(title: "", action: #selector(selectFavoriteModel(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = model.filename
                item.state = isActive ? .on : .off
                
                let style = NSMutableParagraphStyle()
                let tabStop = NSTextTab(textAlignment: .right, location: 260)
                style.tabStops = [tabStop]

                let attrTitle = NSMutableAttributedString(string: "\(model.name)\t\(model.sizeInfo)", attributes: [
                    .font: NSFont.systemFont(ofSize: 13),
                    .paragraphStyle: style
                ])
                let sizeRange = (attrTitle.string as NSString).range(of: model.sizeInfo)
                if sizeRange.location != NSNotFound {
                    attrTitle.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: sizeRange)
                    attrTitle.addAttribute(.font, value: NSFont.systemFont(ofSize: 12), range: sizeRange)
                }
                item.attributedTitle = attrTitle
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        // ── Settings / History / Quit ─────────────────────────────────────
        let historyItem = NSMenuItem(title: "Historique des transcriptions…", action: #selector(openHistory), keyEquivalent: "h")
        historyItem.target = self
        historyItem.image = NSImage(systemSymbolName: "clock", accessibilityDescription: nil)
        menu.addItem(historyItem)
        
        let settingsItem = NSMenuItem(title: "Paramètres…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(title: "Quitter Whispeur", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: nil)
        menu.addItem(quitItem)

        return menu
    }

    // MARK: - State updates (called from coordinator observation)

    func updateIcon(for state: PipelineState) {
        guard let button = statusItem.button else { return }

        spinTimer?.invalidate()
        spinTimer = nil
        
        // Use pointSize and weight to exactly match the Apple Control Center mic icon
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)

        var shouldSpin = false

        switch state {
        case .idle:
            button.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "Whispeur")?.withSymbolConfiguration(config)
            button.contentTintColor = nil

        case .loadingModel:
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Enregistrement…")?.withSymbolConfiguration(config)
            button.contentTintColor = .systemOrange

        case .recording:
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Enregistrement…")?.withSymbolConfiguration(config)
            button.contentTintColor = .systemOrange

        case .transcribing:
            button.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "Transcription…")?.withSymbolConfiguration(config)
            button.contentTintColor = nil
            shouldSpin = true

        case .pasting:
            button.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "Whispeur")?.withSymbolConfiguration(config)
            button.contentTintColor = nil

        case .error:
            button.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "Erreur")?.withSymbolConfiguration(config)
            button.contentTintColor = .systemRed
        }
        
        button.image?.isTemplate = (button.contentTintColor == nil)
        
        if shouldSpin {
            baseSpinImage = button.image
            spinAngle = 0
            spinTimer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [weak self] _ in
                // Timer.scheduledTimer always fires on the main run loop thread.
                MainActor.assumeIsolated { self?.tickSpin() }
            }
        }
    }

    private func tickSpin() {
        guard let button = statusItem.button, let base = baseSpinImage else { return }
        spinAngle -= .pi / 15
        if spinAngle <= -.pi * 2 { spinAngle += .pi * 2 }
        
        let size = base.size
        let img = NSImage(size: size)
        img.lockFocus()
        if let ctx = NSGraphicsContext.current?.cgContext {
            ctx.translateBy(x: size.width / 2, y: size.height / 2)
            ctx.rotate(by: spinAngle)
            ctx.translateBy(x: -size.width / 2, y: -size.height / 2)
        }
        base.draw(at: .zero, from: .zero, operation: .copy, fraction: 1.0)
        img.unlockFocus()
        img.isTemplate = base.isTemplate
        button.image = img
    }

    // MARK: - Actions

    @objc private func triggerRecording() {
        logger.debug("triggerRecording() — state: \(String(describing: self.coordinator.pipelineState))")
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
        logger.debug("Selecting favorite model: \(filename)")
        settings.selectedModelFilename = filename
        coordinator.modelURL = descriptor.localURL
    }

    @objc func openSettings() {
        openSettingsWindow(tab: .general) // Default to general
    }

    @objc func openSettingsToHotkey() {
        openSettingsWindow(tab: .general)
    }

    private func openSettingsWindow(tab: SettingsTab) {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            // Note: Since SettingsView uses @State for its tab, changing the tab of an already 
            // open window requires passing a binding or just re-creating the view. 
            // For simplicity, we just bring it forward. If it's already open, they can click the tab.
            return
        }

        let settings = AppSettings.shared
        let view = SettingsView(
            settings: settings,
            coordinator: coordinator,
            micManager: micPermissionManager,
            historyService: historyService,
            initialTab: tab
        )
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
            self?.settingsWindowDelegate = nil
        }
        settingsWindowDelegate = closeDelegate
        window.delegate = closeDelegate
        settingsWindow = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    @objc func openHistory() {
        openSettingsWindow(tab: .history)
    }
}

// MARK: - NSMenuDelegate

extension StatusBarController: NSMenuDelegate {
    /// Called by macOS just before the menu is displayed — rebuild contents fresh.
    func menuWillOpen(_ menu: NSMenu) {
        logger.debug("menuWillOpen — rebuilding \(self.settings.favoritedModelDescriptors.filter(\.isDownloaded).count) favorites")
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
