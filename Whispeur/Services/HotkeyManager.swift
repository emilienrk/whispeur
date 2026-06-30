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

    /// State shared with the tap thread. Only mutated on MainActor (tap must be off).
    nonisolated(unsafe) private var tapState = TapSharedState()
    nonisolated(unsafe) private var runLoopSource: CFRunLoopSource?
    nonisolated(unsafe) private var runLoopThread: Thread?

    // MARK: - Init / Deinit

    init() {
        hasAccessibilityPermission = AXIsProcessTrusted()
    }

    deinit {
        // deinit is nonisolated — access nonisolated(unsafe) fields directly.
        if let tap = tapState.eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let src = runLoopSource {
            CFRunLoopSourceInvalidate(src)
        }
        runLoopThread?.cancel()
    }

    // MARK: - Public API

    func checkAccessibilityPermission() {
        hasAccessibilityPermission = AXIsProcessTrusted()
    }

    func openAccessibilityPreferences() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    func startListening() {
        guard !isListening else { return }
        hasAccessibilityPermission = AXIsProcessTrusted()
        guard hasAccessibilityPermission else { return }
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
        tapState.hotKey = newKey
        if wasListening { installEventTap() }
    }

    func setMode(_ newMode: HotKeyMode) {
        mode = newMode
        tapState.mode = newMode
        tapState.isToggledOn = false
    }

    // MARK: - CGEventTap lifecycle

    private func installEventTap() {
        // Copy UI state into the shared struct before enabling the tap.
        tapState.hotKey      = hotKey
        tapState.mode        = mode
        tapState.isToggledOn = false

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
            hasAccessibilityPermission = false
            return
        }

        tapState.eventTap = tap

        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = src

        let thread = Thread { [src] in
            CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
            CFRunLoopRun()
        }
        thread.name = "com.whispeur.hotkeyrunloop"
        thread.qualityOfService = .userInteractive
        thread.start()
        runLoopThread = thread

        CGEvent.tapEnable(tap: tap, enable: true)
        isListening = true
    }

    private func shutdownTap() {
        if let tap = tapState.eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            tapState.eventTap = nil
        }
        if let src = runLoopSource {
            CFRunLoopSourceInvalidate(src)
            runLoopSource = nil
        }
        runLoopThread?.cancel()
        runLoopThread = nil
    }

    // MARK: - Event handling (called from tap thread — nonisolated)

    nonisolated func handleRawEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {

        // Re-enable the tap if the system disabled it.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = tapState.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown || type == .keyUp else {
            return Unmanaged.passUnretained(event)
        }

        // Check key code.
        let eventKeyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        guard eventKeyCode == tapState.hotKey.keyCode else {
            return Unmanaged.passUnretained(event)
        }

        // Check modifier flags.
        let relevantMask = CGEventFlags.maskControl.rawValue
                         | CGEventFlags.maskAlternate.rawValue
                         | CGEventFlags.maskShift.rawValue
                         | CGEventFlags.maskCommand.rawValue
        let strippedFlags   = CGEventFlags(rawValue: event.flags.rawValue & relevantMask)
        let targetModifiers = CGEventFlags(rawValue: UInt64(tapState.hotKey.modifiers))
        guard strippedFlags == targetModifiers else {
            return Unmanaged.passUnretained(event)
        }

        // Dispatch to recording logic.
        switch type {
        case .keyDown: fireKeyDown()
        case .keyUp:   fireKeyUp()
        default:       break
        }

        // Consume the event — don't forward to other apps.
        return nil
    }

    nonisolated private func fireKeyDown() {
        switch tapState.mode {
        case .pushToTalk:
            DispatchQueue.main.async { [weak self] in self?.onKeyDown?() }

        case .toggle:
            if !tapState.isToggledOn {
                tapState.isToggledOn = true
                DispatchQueue.main.async { [weak self] in self?.onKeyDown?() }
            } else {
                tapState.isToggledOn = false
                DispatchQueue.main.async { [weak self] in self?.onKeyUp?() }
            }
        }
    }

    nonisolated private func fireKeyUp() {
        switch tapState.mode {
        case .pushToTalk:
            DispatchQueue.main.async { [weak self] in self?.onKeyUp?() }
        case .toggle:
            break  // Toggle stops on second keyDown, not on keyUp.
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
