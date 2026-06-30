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

    /// Default: Right Option key, no additional modifiers.
    static let defaultHotKey = HotKey(keyCode: 61, modifiers: 0)

    private static func keyCodeToString(_ keyCode: Int) -> String? {
        let map: [Int: String] = [
            36: "↩", 48: "⇥", 49: "Space", 51: "⌫",
            53: "Esc", 61: "⌥R",
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z",
            7: "X", 8: "C", 9: "V", 11: "B", 12: "Q", 13: "W",
            14: "E", 15: "R", 16: "Y", 17: "T", 31: "O", 32: "U",
            34: "I", 35: "P", 37: "L", 38: "J", 39: "'",
            40: "K", 41: ";", 45: "N", 46: "M",
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
        case .toggle:     return "Appuyer deux fois"
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
        print("[Hotkey] checkAccessibilityPermission() -> \(trusted)")
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
        print("[Hotkey] promptAccessibilityPermission() -> \(trusted)")
        hasAccessibilityPermission = trusted
        return trusted
    }

    /// Poll every 1.5 seconds until permission is granted, then start listening.
    func startPollingAccessibility() {
        guard accessibilityPollTask == nil else {
            print("[Hotkey] startPollingAccessibility() skipped — already polling")
            return
        }
        print("[Hotkey] Starting accessibility polling...")
        accessibilityPollTask = Task { [weak self] in
            while true {
                try? await Task.sleep(for: .seconds(1.5))
                guard let self else { return }
                let trusted = AXIsProcessTrusted()
                print("[Hotkey] Poll tick: AXIsProcessTrusted=\(trusted)")
                self.hasAccessibilityPermission = trusted
                if trusted {
                    print("[Hotkey] Accessibility granted! Starting listener...")
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
        print("[Hotkey] Stopped accessibility polling")
    }

    func startListening() {
        guard !isListening else {
            print("[Hotkey] startListening() skipped — already listening")
            return
        }
        hasAccessibilityPermission = AXIsProcessTrusted()
        print("[Hotkey] startListening() — AXIsProcessTrusted=\(hasAccessibilityPermission)")
        guard hasAccessibilityPermission else {
            print("[Hotkey] startListening() aborted — no accessibility permission")
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

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: hotkeyEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("[Hotkey] CGEvent.tapCreate failed — accessibility permission revoked?")
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
        print("[Hotkey] Event tap installed ✅")
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
        print("[Hotkey] Event tap shut down")
    }

    // MARK: - Event handling (called from tap thread — nonisolated)

    nonisolated func handleRawEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {

        // Re-enable the tap if the system disabled it.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = tapBox.tapState.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown || type == .keyUp else {
            return Unmanaged.passUnretained(event)
        }

        // Check key code.
        let eventKeyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        guard eventKeyCode == tapBox.tapState.hotKey.keyCode else {
            return Unmanaged.passUnretained(event)
        }

        // Check modifier flags.
        let relevantMask = CGEventFlags.maskControl.rawValue
                         | CGEventFlags.maskAlternate.rawValue
                         | CGEventFlags.maskShift.rawValue
                         | CGEventFlags.maskCommand.rawValue
        var eventFlagsRaw = event.flags.rawValue & relevantMask
        let targetModifiersRaw = UInt64(tapBox.tapState.hotKey.modifiers)

        let modifierKeyCodes: Set<Int> = [54, 55, 56, 57, 58, 59, 60, 61, 62]
        if modifierKeyCodes.contains(eventKeyCode) {
            if eventKeyCode == 58 || eventKeyCode == 61 { eventFlagsRaw &= ~CGEventFlags.maskAlternate.rawValue }
            if eventKeyCode == 54 || eventKeyCode == 55 { eventFlagsRaw &= ~CGEventFlags.maskCommand.rawValue }
            if eventKeyCode == 56 || eventKeyCode == 60 { eventFlagsRaw &= ~CGEventFlags.maskShift.rawValue }
            if eventKeyCode == 59 || eventKeyCode == 62 { eventFlagsRaw &= ~CGEventFlags.maskControl.rawValue }
        }

        guard eventFlagsRaw == targetModifiersRaw else {
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .keyDown: fireKeyDown()
        case .keyUp:   fireKeyUp()
        default:       break
        }

        return nil
    }

    nonisolated private func fireKeyDown() {
        switch tapBox.tapState.mode {
        case .pushToTalk:
            DispatchQueue.main.async { [weak self] in self?.onKeyDown?() }

        case .toggle:
            if !tapBox.tapState.isToggledOn {
                tapBox.tapState.isToggledOn = true
                DispatchQueue.main.async { [weak self] in self?.onKeyDown?() }
            } else {
                tapBox.tapState.isToggledOn = false
                DispatchQueue.main.async { [weak self] in self?.onKeyUp?() }
            }
        }
    }

    nonisolated private func fireKeyUp() {
        switch tapBox.tapState.mode {
        case .pushToTalk:
            DispatchQueue.main.async { [weak self] in self?.onKeyUp?() }
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
