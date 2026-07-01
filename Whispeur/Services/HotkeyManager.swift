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
        return parts.joined()
    }

    /// Default: fn key (63), matching Wispr Flow behavior.
    static let defaultHotKey = HotKey(keyCode: 63, modifiers: 0)

    private static func keyCodeToString(_ keyCode: Int) -> String? {
        let map: [Int: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 
            11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 
            20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 
            29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "↩", 37: "L", 
            38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 
            47: ".", 48: "⇥", 49: "Espace", 50: "`", 51: "⌫", 52: "Enter", 53: "Esc", 54: "⌘", 
            55: "⌘", 56: "⇧", 57: "⇪", 58: "⌥", 59: "⌃", 60: "⇧", 
            61: "⌥", 62: "⌃", 65: ".", 67: "*", 69: "+", 71: "Clear", 75: "/", 
            76: "Enter", 78: "-", 81: "=", 82: "0", 83: "1", 84: "2", 85: "3", 86: "4", 87: "5", 
            88: "6", 89: "7", 91: "8", 92: "9", 96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 
            101: "F9", 103: "F11", 105: "F13", 106: "F16", 107: "F14", 109: "F10", 111: "F12", 
            113: "F15", 114: "Help", 115: "Home", 116: "PgUp", 117: "⌦", 118: "F4", 119: "End", 
            120: "F2", 121: "PgDn", 122: "F1", 123: "←", 124: "→", 125: "↓", 126: "↑",
            63: "fn"
        ]
        return map[keyCode]
    }
}

/// How the hotkey triggers recording.
enum HotKeyMode: String, Codable, CaseIterable, Sendable {
    case pushToTalk = "pushToTalk"
    case toggle     = "toggle"

    var displayName: String {
        switch self {
        case .pushToTalk: return "Maintenir enfoncé"
        case .toggle:     return "Basculer (un clic start/stop)"
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
            logger.warning("startListening() aborted — no accessibility permission")
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

    // MARK: - CGEventTap lifecycle

    private func installEventTap() {
        // Copy UI state into the tap container before enabling the tap.
        tapBox.tapState.hotKey      = hotKey
        tapBox.tapState.mode        = mode
        tapBox.tapState.isToggledOn = false

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

        // On n'agit QUE si c'est la touche principale du raccourci.
        guard eventKeyCode == targetKeyCode else {
            return Unmanaged.passUnretained(event)
        }

        // Vérifier la concordance des modificateurs.
        guard eventFlagsRaw == targetModifiersRaw else {
            // Les modificateurs ne correspondent pas.
            // Si c'est un relâchement (keyUp ou flagsChanged-off), on envoie quand même keyUp
            // pour éviter un état bloqué (ex: modificateur relâché avant la touche de base).
            let isRelease: Bool
            if type == .flagsChanged {
                isRelease = !isModifierDown
            } else {
                isRelease = (type == .keyUp)
            }
            if isRelease {
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
            fireKeyDown()
        } else {
            fireKeyUp()
        }
        return nil
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
