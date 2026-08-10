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
    private let coordinator: RecordingCoordinator
    private let settings: AppSettings
    private let historyService: HistoryService
    private let micPermissionManager: MicrophonePermissionManager
    private let servicesContainer: ServicesContainer

    /// Overlaid on the button while transcribing: NSStatusBarButton takes no
    /// symbol effects, so the animation lives in a hosted SwiftUI view where
    /// `.symbolEffect` is the API meant for it.
    private var spinnerView: NSHostingView<TranscribingSpinner>?

    private var recordingTimer: Timer?
    private var recordingStartTime: Date?

    // The persistent NSMenu assigned once — content rebuilt in menuWillOpen.
    private let persistentMenu = NSMenu()


    // MARK: - Init

    init(coordinator: RecordingCoordinator, settings: AppSettings = .shared, historyService: HistoryService, micPermissionManager: MicrophonePermissionManager, servicesContainer: ServicesContainer) {
        self.coordinator = coordinator
        self.settings = settings
        self.historyService = historyService
        self.micPermissionManager = micPermissionManager
        self.servicesContainer = servicesContainer
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
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
            triggerTitle  = String(localized: "Démarrer l'enregistrement")
            triggerAction = #selector(triggerRecording)
        case .loadingModel:
            triggerTitle  = String(localized: "Arrêter l'enregistrement")
            triggerAction = #selector(triggerRecording)
        case .recording:
            triggerTitle  = String(localized: "Arrêter l'enregistrement")
            triggerAction = #selector(triggerRecording)
        case .transcribing:
            triggerTitle  = String(localized: "Transcription en cours…")
            triggerAction = nil
        case .pasting:
            triggerTitle  = String(localized: "Collage en cours…")
            triggerAction = nil
        case .error(let msg):
            triggerTitle  = String(localized: "Erreur") + " : \(msg)"
            triggerAction = nil
        }

        let triggerItem = NSMenuItem(title: triggerTitle, action: triggerAction, keyEquivalent: "")
        triggerItem.target = self
        triggerItem.isEnabled = triggerAction != nil
        menu.addItem(triggerItem)

        menu.addItem(.separator())

        // ── Favorite models ───────────────────────────────────────────────
        let favorites = settings.favoritedModelDescriptors.filter { ModelManager.shared.isInstalled($0) }
        if !favorites.isEmpty {
            let favHeader = NSMenuItem(title: String(localized: "Modèles favoris"), action: nil, keyEquivalent: "")
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
        let historyItem = NSMenuItem(title: String(localized: "Historique des transcriptions…"), action: #selector(openHistory), keyEquivalent: "h")
        historyItem.target = self
        historyItem.image = NSImage(systemSymbolName: "clock", accessibilityDescription: nil)
        menu.addItem(historyItem)
        
        let updateItem = NSMenuItem(title: String(localized: "Vérifier les mises à jour…"), action: #selector(checkForUpdates), keyEquivalent: "")
        updateItem.target = self
        updateItem.image = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: nil)
        menu.addItem(updateItem)

        let settingsItem = NSMenuItem(title: String(localized: "Paramètres…"), action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(title: String(localized: "Quitter Whispeur"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: nil)
        menu.addItem(quitItem)

        return menu
    }

    // MARK: - State updates (called from coordinator observation)

    func updateIcon(for state: PipelineState) {
        guard let button = statusItem.button else { return }

        // Only invalidate the recording timer if we are leaving a recording state
        let isRecordingState = (state == .loadingModel || state == .recording)
        if !isRecordingState {
            recordingTimer?.invalidate()
            recordingTimer = nil
            button.title = ""
        }
        
        if state != .transcribing { stopSpinner() }

        // Use pointSize and weight to exactly match the Apple Control Center mic icon
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)

        var shouldSpin = false

        switch state {
        case .idle:
            button.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "Whispeur")?.withSymbolConfiguration(config)
            button.contentTintColor = nil

        case .loadingModel, .recording:
            button.image = nil
            button.contentTintColor = nil
            
            if recordingTimer == nil {
                button.title = "0:00"
                recordingStartTime = Date()
                let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.updateRecordingTimer() }
                }
                RunLoop.current.add(t, forMode: .common)
                recordingTimer = t
            }

        case .transcribing:
            button.contentTintColor = nil
            if spinnerView == nil {
                button.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "Transcription…")?.withSymbolConfiguration(config)
                shouldSpin = true
            }

        case .pasting:
            button.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "Whispeur")?.withSymbolConfiguration(config)
            button.contentTintColor = nil

        case .error:
            button.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "Erreur")?.withSymbolConfiguration(config)
            button.contentTintColor = .systemRed
        }
        
        button.image?.isTemplate = (button.contentTintColor == nil)
        
        if shouldSpin { startSpinner(on: button) }
    }

    private func startSpinner(on button: NSStatusBarButton) {
        guard spinnerView == nil, let image = button.image else { return }

        let view = NSHostingView(rootView: TranscribingSpinner())
        view.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(view)
        NSLayoutConstraint.activate([
            view.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            view.centerYAnchor.constraint(equalTo: button.centerYAnchor)
        ])
        spinnerView = view

        // Swap the button's own image for a blank one of the same size: the
        // status item keeps its width, and only the overlay is seen turning.
        let placeholder = NSImage(size: image.size)
        placeholder.isTemplate = true
        button.image = placeholder
    }

    private func stopSpinner() {
        // The effect is owned by the view — dropping it stops the animation.
        spinnerView?.removeFromSuperview()
        spinnerView = nil
    }


    private func updateRecordingTimer() {
        guard let button = statusItem.button,
              let startTime = recordingStartTime else { return }
        
        let elapsed = Date().timeIntervalSince(startTime)
        let minutes = Int(elapsed) / 60
        let seconds = Int(elapsed) % 60
        
        // Add monospaced digit font so the text width doesn't jitter
        let font = NSFont.monospacedDigitSystemFont(ofSize: 13.0, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        button.attributedTitle = NSAttributedString(string: String(format: "%d:%02d", minutes, seconds), attributes: attributes)
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

    @objc private func checkForUpdates() {
        UpdaterService.shared.checkForUpdates()
    }

    @objc func openSettings() {
        SettingsWindowController.shared.show(services: servicesContainer)
    }


    @objc func openHistory() {
        SettingsWindowController.shared.show(services: servicesContainer, tab: .history)
    }
}

// MARK: - Transcription spinner

/// Matches the point size and weight of the idle mic symbol, so the overlay
/// lands exactly where the button's own image sat.
struct TranscribingSpinner: View {
    var body: some View {
        Image(systemName: "arrow.triangle.2.circlepath")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Color(nsColor: .labelColor))
            .symbolEffect(.rotate, options: .repeating)
            .accessibilityLabel(Text("Transcription en cours…"))
    }
}

// MARK: - NSMenuDelegate

extension StatusBarController: NSMenuDelegate {
    /// Called by macOS just before the menu is displayed — rebuild contents fresh.
    func menuWillOpen(_ menu: NSMenu) {
        logger.debug("menuWillOpen — rebuilding \(self.settings.favoritedModelDescriptors.count) favorites")
        let fresh = buildMenu()
        menu.removeAllItems()
        // Move items from the temp menu into the persistent menu.
        while let item = fresh.items.first {
            fresh.removeItem(item)
            menu.addItem(item)
        }
    }
}


