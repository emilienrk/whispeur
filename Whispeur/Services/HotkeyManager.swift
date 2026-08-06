// HotkeyManager.swift
// Whispeur
//
// Global keyboard shortcut listener using CGEventTap.
// Works even when the app is in the background (no focus required).
// Supports Push-to-Talk and Toggle modes.
//
// Swift 6 concurrency design:
// - Observable state (isListening, hotKey, mode) is @MainActor.
// - The CGEventTap callback fires on a private CFRunLoop thread.
// - A separate `TapState` struct (nonisolated(unsafe)) carries the copies
//   needed by the callback. Updated only on MainActor, before tap starts.
//   This is safe but not statically verified → nonisolated(unsafe).

@preconcurrency import CoreFoundation
import AppKit
import ApplicationServices
import Carbon.HIToolbox
import os

private let logger = Logger(subsystem: "com.whispeur", category: "HotkeyManager")

// MARK: - Hotkey Models

/// A key combination (modifier flags + key code).
struct HotKey: Equatable, Sendable, Codable {
    let keyCode: Int
    let modifiers: Int  // Masked CGEventFlags raw value

    var displayString: String {
        var parts: [String] = []
        let flags = CGEventFlags(rawValue: UInt64(modifiers))
        if flags.contains(.maskControl)   { parts.append("⌃") }
        if flags.contains(.maskAlternate) { parts.append("⌥") }
        if flags.contains(.maskShift)     { parts.append("⇧") }
        if flags.contains(.maskCommand)   { parts.append("⌘") }
        parts.append(Self.keyCodeToString(keyCode) ?? "[\(keyCode)]")
        return parts.joined(separator: " ")
    }

    /// Default: Dictation key 🎤 (176) — replaces Apple Dictation with Whisper.
    /// (160 is Mission Control/F3, not the dictation key.)
    static let defaultHotKey = HotKey(keyCode: 176, modifiers: 0)

    private static func keyCodeToString(_ keyCode: Int) -> String? {
        // Touches spéciales et de fonction
        let specialMap: [Int: String] = [
            36: "↩", 48: "⇥", 49: "Espace", 51: "⌫", 52: "Enter", 53: "Esc", 
            54: "⌘", 55: "⌘", 56: "⇧", 57: "⇪", 58: "⌥", 59: "⌃", 60: "⇧", 
            61: "⌥", 62: "⌃", 63: "fn", 71: "Clear", 76: "Enter", 
            96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9", 
            103: "F11", 105: "F13", 106: "F16", 107: "F14", 109: "F10", 111: "F12", 
            113: "F15", 114: "Help", 115: "Home", 116: "PgUp", 117: "⌦", 118: "F4", 
            119: "End", 120: "F2", 121: "PgDn", 122: "F1", 123: "←", 124: "→", 
            125: "↓", 126: "↑", 160: "Mission Control", 176: "Dictée"
        ]
        
        if let special = specialMap[keyCode] {
            return special
        }
        
        // Résolution dynamique pour les touches alphanumériques selon le layout clavier (QWERTY/AZERTY...)
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        guard let layoutDataPtr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let layoutData = unsafeBitCast(layoutDataPtr, to: CFData.self)
        let keyLayoutPtr = unsafeBitCast(CFDataGetBytePtr(layoutData), to: UnsafePointer<UCKeyboardLayout>.self)
        
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var actualLength = 0
        
        let status = UCKeyTranslate(
            keyLayoutPtr,
            UInt16(keyCode),
            UInt16(kUCKeyActionDown),
            0,
            UInt32(LMGetKbdType()),
            UInt32(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            4,
            &actualLength,
            &chars
        )
        
        if status == noErr && actualLength > 0 {
            return String(utf16CodeUnits: chars, count: actualLength).uppercased()
        }
        
        return nil
    }
}

/// How the hotkey triggers recording.
enum HotKeyMode: String, Codable, CaseIterable, Sendable {
    case pushToTalk = "pushToTalk"
    case toggle     = "toggle"

    var displayName: String {
        switch self {
        case .pushToTalk: return String(localized: "Maintenir enfoncé")
        case .toggle:     return String(localized: "Basculer (un clic start/stop)")
        }
    }
}

// MARK: - TapSharedState

/// Mutable state accessed by the CGEventTap callback thread.
/// INVARIANT: only mutated on the MainActor while the tap is stopped.
private struct TapSharedState {
    var hotKey: HotKey       = .defaultHotKey
    var mode: HotKeyMode     = .pushToTalk
    var isToggledOn: Bool    = false
    /// True entre le keyDown du raccourci et son relâchement — permet de ne
    /// consommer le keyUp "anti-blocage" que si un appui est réellement en cours.
    var isKeyEngaged: Bool   = false
    /// True pendant la capture d'un nouveau raccourci (recorder des réglages).
    var isCapturing: Bool    = false
    /// Modificateur enfoncé pendant la capture (bindé seul à son relâchement).
    var pendingCaptureModifier: Int?
    var eventTap: CFMachPort?
}

// MARK: - TapStateContainer
// A plain class (NOT @Observable) that holds all state accessed from the
// CGEventTap callback thread. Stored as a `let` in HotkeyManager so the
// @Observable macro does NOT wrap it with queue-checking tracking code.
private final class TapStateContainer: @unchecked Sendable {
    var tapState     = TapSharedState()
    var runLoopSource: CFRunLoopSource?
    var runLoopThread: Thread?
}

// MARK: - HotkeyManager

@MainActor
@Observable
final class HotkeyManager {

    // MARK: - Observable properties (UI-facing, MainActor)

    private(set) var isListening: Bool          = false
    private(set) var hotKey: HotKey             = .defaultHotKey
    private(set) var mode: HotKeyMode           = .pushToTalk
    private(set) var hasAccessibilityPermission = false

    // MARK: - Callbacks (dispatched to MainActor)

    var onKeyDown: (@MainActor () -> Void)?
    var onKeyUp:   (@MainActor () -> Void)?

    // MARK: - Tap infrastructure
    // `let` property — @Observable does NOT generate observation tracking for `let`.
    // Accessing tapBox from the CGEventTap thread is therefore safe.
    private let tapBox = TapStateContainer()

    // MARK: - Accessibility polling
    private(set) var accessibilityPollTask: Task<Void, Never>?

    // MARK: - Init / Deinit

    init() {
        hasAccessibilityPermission = AXIsProcessTrusted()
    }

    deinit {
        if let tap = tapBox.tapState.eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let src = tapBox.runLoopSource {
            CFRunLoopSourceInvalidate(src)
        }
        tapBox.runLoopThread?.cancel()
    }

    // MARK: - Public API

    func checkAccessibilityPermission() {
        let trusted = AXIsProcessTrusted()
        logger.debug("checkAccessibilityPermission() -> \(trusted)")
        hasAccessibilityPermission = trusted
    }

    func openAccessibilityPreferences() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    /// Requests the accessibility permission dialog to appear (if not yet granted).
    /// Returns true if already trusted.
    @discardableResult
    func promptAccessibilityPermission() -> Bool {
        // Use the raw string key to avoid Swift 6 concurrency issues with kAXTrustedCheckOptionPrompt.
        let options: CFDictionary = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        logger.debug("promptAccessibilityPermission() -> \(trusted)")
        hasAccessibilityPermission = trusted
        return trusted
    }

    /// Poll every 1.5 seconds until permission is granted, then start listening.
    func startPollingAccessibility() {
        guard accessibilityPollTask == nil else {
            logger.debug("startPollingAccessibility() skipped — already polling")
            return
        }
        logger.info("Starting accessibility polling...")
        accessibilityPollTask = Task { [weak self] in
            while true {
                try? await Task.sleep(for: .seconds(1.5))
                guard let self else { return }
                let trusted = AXIsProcessTrusted()
                logger.debug("Poll tick: AXIsProcessTrusted=\(trusted)")
                self.hasAccessibilityPermission = trusted
                if trusted {
                    logger.info("Accessibility granted! Starting listener...")
                    if !self.isListening { self.startListening() }
                    break
                }
            }
            self?.accessibilityPollTask = nil
        }
    }

    func stopPollingAccessibility() {
        accessibilityPollTask?.cancel()
        accessibilityPollTask = nil
        logger.debug("Stopped accessibility polling")
    }

    func startListening() {
        guard !isListening else {
            logger.debug("startListening() skipped — already listening")
            return
        }
        hasAccessibilityPermission = AXIsProcessTrusted()
        logger.debug("startListening() — AXIsProcessTrusted=\(self.hasAccessibilityPermission)")
        guard hasAccessibilityPermission else {
            // Granting Accessibility does not notify us, and the tap can only be
            // installed once trusted — without this poll the hotkey stays dead
            // until the next launch.
            logger.warning("startListening() deferred — no accessibility permission, polling")
            startPollingAccessibility()
            return
        }
        installEventTap()
    }

    func stopListening() {
        guard isListening else { return }
        shutdownTap()
        isListening = false
    }

    func updateHotKey(_ newKey: HotKey) {
        let wasListening = isListening
        if wasListening { shutdownTap() }
        hotKey = newKey
        tapBox.tapState.hotKey = newKey
        if wasListening { installEventTap() }
    }

    func setMode(_ newMode: HotKeyMode) {
        mode = newMode
        tapBox.tapState.mode = newMode
        tapBox.tapState.isToggledOn = false
    }

    // MARK: - Hotkey capture (settings recorder)

    /// Callback de capture, livré sur le MainActor. Nil = capture annulée (Échap).
    private var captureCompletion: (@MainActor (HotKey?) -> Void)?

    /// Capture la prochaine touche (ou modificateur seul) comme nouveau raccourci,
    /// en consommant l'événement. C'est la seule voie qui voit les touches
    /// spéciales comme 🎤 (176), invisibles aux moniteurs NSEvent.
    /// Retourne true si le tap est actif (la capture aura bien lieu) ;
    /// false si l'appelant doit se replier sur des moniteurs NSEvent.
    @discardableResult
    func beginHotKeyCapture(_ completion: @escaping @MainActor (HotKey?) -> Void) -> Bool {
        captureCompletion?(nil)
        captureCompletion = completion
        tapBox.tapState.pendingCaptureModifier = nil
        tapBox.tapState.isCapturing = true
        return isListening
    }

    func cancelHotKeyCapture() {
        tapBox.tapState.isCapturing = false
        tapBox.tapState.pendingCaptureModifier = nil
        let completion = captureCompletion
        captureCompletion = nil
        completion?(nil)
    }

    /// Appelé depuis le thread du tap quand une touche a été capturée (ou Échap).
    nonisolated private func completeCapture(with key: HotKey?) {
        tapBox.tapState.isCapturing = false
        tapBox.tapState.pendingCaptureModifier = nil
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let completion = self.captureCompletion
            self.captureCompletion = nil
            completion?(key)
        }
    }

    // MARK: - CGEventTap lifecycle

    private func installEventTap() {
        // Copy UI state into the tap container before enabling the tap.
        tapBox.tapState.hotKey       = hotKey
        tapBox.tapState.mode         = mode
        tapBox.tapState.isToggledOn  = false
        tapBox.tapState.isKeyEngaged = false

        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
                              | (1 << CGEventType.keyUp.rawValue)
                              | (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: hotkeyEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            logger.error("CGEvent.tapCreate failed — accessibility permission revoked?")
            hasAccessibilityPermission = false
            return
        }

        tapBox.tapState.eventTap = tap

        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        tapBox.runLoopSource = src

        // `src` captured by value into the thread closure (safe: CFRunLoopSource is a CF ref).
        let srcForThread: CFRunLoopSource = src!
        let thread = Thread {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), srcForThread, .commonModes)
            CFRunLoopRun()
        }
        thread.name = "com.whispeur.hotkeyrunloop"
        thread.qualityOfService = .userInteractive
        thread.start()
        tapBox.runLoopThread = thread

        CGEvent.tapEnable(tap: tap, enable: true)
        isListening = true
        logger.info("Event tap installed ✅")
    }

    private func shutdownTap() {
        if let tap = tapBox.tapState.eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            tapBox.tapState.eventTap = nil
        }
        if let src = tapBox.runLoopSource {
            CFRunLoopSourceInvalidate(src)
            tapBox.runLoopSource = nil
        }
        tapBox.runLoopThread?.cancel()
        tapBox.runLoopThread = nil
        logger.debug("Event tap shut down")
    }

    // MARK: - Event handling (called from tap thread — nonisolated)

    nonisolated func handleRawEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = tapBox.tapState.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown || type == .keyUp || type == .flagsChanged else {
            return Unmanaged.passUnretained(event)
        }

        let eventKeyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let targetKeyCode = tapBox.tapState.hotKey.keyCode
        let targetModifiersRaw = UInt64(tapBox.tapState.hotKey.modifiers)

        let relevantMask = CGEventFlags.maskControl.rawValue
                         | CGEventFlags.maskAlternate.rawValue
                         | CGEventFlags.maskShift.rawValue
                         | CGEventFlags.maskCommand.rawValue
        var eventFlagsRaw = event.flags.rawValue & relevantMask

        // Pour les touches de modification utilisées comme touche principale :
        // on soustrait leur propre flag pour ignorer l'auto-modification.
        var isModifierDown = false
        let modifierKeyCodes: Set<Int> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
        if modifierKeyCodes.contains(eventKeyCode) {
            if eventKeyCode == 58 || eventKeyCode == 61 {
                isModifierDown = (eventFlagsRaw & CGEventFlags.maskAlternate.rawValue) != 0
                eventFlagsRaw &= ~CGEventFlags.maskAlternate.rawValue
            } else if eventKeyCode == 54 || eventKeyCode == 55 {
                isModifierDown = (eventFlagsRaw & CGEventFlags.maskCommand.rawValue) != 0
                eventFlagsRaw &= ~CGEventFlags.maskCommand.rawValue
            } else if eventKeyCode == 56 || eventKeyCode == 60 {
                isModifierDown = (eventFlagsRaw & CGEventFlags.maskShift.rawValue) != 0
                eventFlagsRaw &= ~CGEventFlags.maskShift.rawValue
            } else if eventKeyCode == 59 || eventKeyCode == 62 {
                isModifierDown = (eventFlagsRaw & CGEventFlags.maskControl.rawValue) != 0
                eventFlagsRaw &= ~CGEventFlags.maskControl.rawValue
            } else if eventKeyCode == 63 {
                // fn uses maskSecondaryFn; strip it so modifier comparison stays clean.
                isModifierDown = event.flags.contains(.maskSecondaryFn)
                eventFlagsRaw &= ~CGEventFlags.maskSecondaryFn.rawValue
            }
        }

        // Mode capture (recorder des réglages) : la prochaine touche devient
        // le nouveau raccourci et tout est consommé le temps de la capture.
        if tapBox.tapState.isCapturing {
            return handleCaptureEvent(
                type: type,
                keyCode: eventKeyCode,
                maskedFlags: eventFlagsRaw,
                isModifierDown: isModifierDown
            )
        }

        // On n'agit QUE si c'est la touche principale du raccourci.
        guard eventKeyCode == targetKeyCode else {
            return Unmanaged.passUnretained(event)
        }

        // Vérifier la concordance des modificateurs.
        guard eventFlagsRaw == targetModifiersRaw else {
            // Les modificateurs ne correspondent pas.
            // Si un appui du raccourci est en cours (ex: modificateur relâché
            // avant la touche de base), on termine proprement avec keyUp.
            // Sinon, la touche est un appui ordinaire : elle doit traverser
            // (sans quoi binder ⌥Espace casserait la touche Espace seule).
            let isRelease: Bool
            if type == .flagsChanged {
                isRelease = !isModifierDown
            } else {
                isRelease = (type == .keyUp)
            }
            if isRelease && tapBox.tapState.isKeyEngaged {
                tapBox.tapState.isKeyEngaged = false
                fireKeyUp()
                return nil
            }
            return Unmanaged.passUnretained(event)
        }

        // Modifier OK → déterminer si c'est un appui ou un relâchement.
        let isDown: Bool
        if type == .flagsChanged {
            isDown = isModifierDown
        } else {
            isDown = (type == .keyDown)
        }

        if isDown {
            // Répétition automatique : consommée mais sans re-déclencher,
            // sinon le mode Basculer alterne start/stop en boucle.
            if type == .keyDown, event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
                return nil
            }
            tapBox.tapState.isKeyEngaged = true
            fireKeyDown()
        } else {
            tapBox.tapState.isKeyEngaged = false
            fireKeyUp()
        }
        return nil
    }

    /// Gère un événement pendant la capture d'un nouveau raccourci.
    /// Tout est consommé : ni l'ancien raccourci ni le système (dictée Apple…)
    /// ne doivent réagir pendant qu'on enregistre la combinaison.
    nonisolated private func handleCaptureEvent(
        type: CGEventType,
        keyCode: Int,
        maskedFlags: UInt64,
        isModifierDown: Bool
    ) -> Unmanaged<CGEvent>? {
        switch type {
        case .keyDown:
            if keyCode == 53 {  // Échap annule
                completeCapture(with: nil)
            } else {
                completeCapture(with: HotKey(keyCode: keyCode, modifiers: Int(maskedFlags)))
            }
            return nil

        case .keyUp:
            return nil

        case .flagsChanged:
            let modifierKeyCodes: Set<Int> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
            guard modifierKeyCodes.contains(keyCode) else { return nil }
            if isModifierDown {
                tapBox.tapState.pendingCaptureModifier = keyCode
            } else if tapBox.tapState.pendingCaptureModifier == keyCode {
                // Modificateur seul : bindé à son relâchement (comme un vrai
                // recorder — laisse la possibilité de faire modif+touche).
                completeCapture(with: HotKey(keyCode: keyCode, modifiers: 0))
            }
            return nil

        default:
            return nil
        }
    }

    nonisolated private func fireKeyDown() {
        switch tapBox.tapState.mode {
        case .pushToTalk:
            DispatchQueue.main.async { [weak self] in
                self?.onKeyDown?()
            }

        case .toggle:
            if !tapBox.tapState.isToggledOn {
                tapBox.tapState.isToggledOn = true
                DispatchQueue.main.async { [weak self] in
                    self?.onKeyDown?()
                }
            } else {
                tapBox.tapState.isToggledOn = false
                DispatchQueue.main.async { [weak self] in
                    self?.onKeyUp?()
                }
            }
        }
    }

    nonisolated private func fireKeyUp() {
        switch tapBox.tapState.mode {
        case .pushToTalk:
            DispatchQueue.main.async { [weak self] in
                self?.onKeyUp?()
            }
        case .toggle:
            break
        }
    }
}

// MARK: - C Callback

private func hotkeyEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let ptr = userInfo else { return Unmanaged.passUnretained(event) }
    let manager = Unmanaged<HotkeyManager>.fromOpaque(ptr).takeUnretainedValue()
    return manager.handleRawEvent(type: type, event: event)
}
