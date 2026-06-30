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
    // These fields are accessed from nonisolated contexts (deinit + CGEventTap callback thread).
    // They are only mutated on the MainActor while the tap is stopped — safe but not statically verified.
    nonisolated(unsafe) private var tapState = TapSharedState()
    nonisolated(unsafe) private var runLoopSource: CFRunLoopSource?
    nonisolated(unsafe) private var runLoopThread: Thread?

    // MARK: - Accessibility polling
    private var accessibilityPollTask: Task<Void, Never>?

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

    /// Poll every 2 seconds until permission is granted, then start listening.
    func startPollingAccessibility() {
        guard accessibilityPollTask == nil else { return }
        accessibilityPollTask = Task { [weak self] in
            while true {
                try? await Task.sleep(for: .seconds(2))
                guard let self else { return }
                let trusted = AXIsProcessTrusted()
                self.hasAccessibilityPermission = trusted
                if trusted {
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

        // Capture src as nonisolated(unsafe) to satisfy Swift 6 Sendable check.
        nonisolated(unsafe) let srcForThread: CFRunLoopSource = src!
        let thread = Thread {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), srcForThread, .commonModes)
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
        // Special case: if the hotkey IS a modifier key (e.g. Right Option, keyCode 61),
        // macOS automatically sets maskAlternate in the event flags, so we must
        // ignore that flag from the event when the hotkey keyCode corresponds to a modifier.
        let relevantMask = CGEventFlags.maskControl.rawValue
                         | CGEventFlags.maskAlternate.rawValue
                         | CGEventFlags.maskShift.rawValue
                         | CGEventFlags.maskCommand.rawValue
        var eventFlagsRaw = event.flags.rawValue & relevantMask
        let targetModifiersRaw = UInt64(tapState.hotKey.modifiers)

        // If the hotkey is a lone modifier key, strip its own flag from the event flags
        // because the key itself contributes its own flag while pressed.
        let modifierKeyCodes: Set<Int> = [54, 55, 56, 57, 58, 59, 60, 61, 62] // Cmd, Shift, Ctrl, Option variants
        if modifierKeyCodes.contains(eventKeyCode) {
            // Strip the flag that corresponds to the physical key being pressed.
            // For Right Option (61) / Left Option (58): strip maskAlternate
            if eventKeyCode == 58 || eventKeyCode == 61 { eventFlagsRaw &= ~CGEventFlags.maskAlternate.rawValue }
            // For Right Cmd (54) / Left Cmd (55): strip maskCommand
            if eventKeyCode == 54 || eventKeyCode == 55 { eventFlagsRaw &= ~CGEventFlags.maskCommand.rawValue }
            // For Right Shift (60) / Left Shift (56): strip maskShift
            if eventKeyCode == 56 || eventKeyCode == 60 { eventFlagsRaw &= ~CGEventFlags.maskShift.rawValue }
            // For Right Ctrl (62) / Left Ctrl (59): strip maskControl
            if eventKeyCode == 59 || eventKeyCode == 62 { eventFlagsRaw &= ~CGEventFlags.maskControl.rawValue }
        }

        guard eventFlagsRaw == targetModifiersRaw else {
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
