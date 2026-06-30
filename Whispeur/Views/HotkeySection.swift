// HotkeySection.swift
// Whispeur
//
// Settings tab: hotkey recording and recording mode.

import SwiftUI
import AppKit

struct HotkeySection: View {
    @Bindable var settings: AppSettings
    let hotkeyManager: HotkeyManager

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {

            // MARK: - Recording mode
            SettingsCard {
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(icon: "record.circle", title: "Mode d'enregistrement")
                    VStack(spacing: 4) {
                        ForEach(HotKeyMode.allCases, id: \.self) { mode in
                            ModeRow(
                                mode: mode,
                                isSelected: settings.hotKeyMode == mode,
                                onSelect: {
                                    settings.hotKeyMode = mode
                                    hotkeyManager.setMode(mode)
                                }
                            )
                        }
                    }
                }
            }

            // MARK: - Hotkey recorder
            SettingsCard {
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(icon: "keyboard", title: "Raccourci clavier")

                    HStack {
                        Text("Touche active")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.7))
                        Spacer()
                        HotKeyRecorder(
                            hotKey: Binding(
                                get: { settings.currentHotKey },
                                set: { newKey in
                                    settings.hotKeyCode = newKey.keyCode
                                    settings.hotKeyModifiers = newKey.modifiers
                                    hotkeyManager.updateHotKey(newKey)
                                }
                            )
                        )
                    }

                    Text("Fonctionne même quand Whispeur est en arrière-plan.")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }

            // MARK: - Auto-paste toggle
            SettingsCard {
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(icon: "doc.on.clipboard", title: "Coller automatiquement")

                    Toggle(isOn: $settings.autoPasteEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Collage automatique (⌘V)")
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.85))
                            Text("Requiert la permission Accessibilité")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.35))
                        }
                    }
                    .toggleStyle(.switch)
                }
            }

            // MARK: - Accessibility status
            AccessibilityPermissionCard(hotkeyManager: hotkeyManager)
        }
    }
}

// MARK: - Accessibility permission card

private struct AccessibilityPermissionCard: View {
    let hotkeyManager: HotkeyManager

    var isGranted: Bool { hotkeyManager.hasAccessibilityPermission }

    var body: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(icon: "hand.raised.fill", title: "Permissions")

                if isGranted {
                    // Granted state — compact green badge
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(Color.green.opacity(0.15))
                                .frame(width: 34, height: 34)
                            Image(systemName: "checkmark.shield.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(.green)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Accessibilité accordée")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.9))
                            Text("Le collage automatique est actif.")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                        Spacer()
                        // Small green dot
                        Circle()
                            .fill(Color.green)
                            .frame(width: 7, height: 7)
                            .shadow(color: .green.opacity(0.6), radius: 4)
                    }
                    .frame(minHeight: 44)
                } else {
                    // Not granted — prominent call-to-action
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(Color.orange.opacity(0.15))
                                    .frame(width: 34, height: 34)
                                Image(systemName: "exclamationmark.shield.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.orange)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Accessibilité requise")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.9))
                                Text("Sans cette permission, Whispeur ne peut pas simuler ⌘V.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.white.opacity(0.4))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                        }

                        Button {
                            // promptAccessibilityPermission() shows the macOS system dialog
                            // AND opens the Accessibility prefs pane if needed.
                            if !hotkeyManager.promptAccessibilityPermission() {
                                hotkeyManager.openAccessibilityPreferences()
                                hotkeyManager.startPollingAccessibility()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.up.right.square")
                                    .font(.system(size: 12))
                                Text("Ouvrir Confidentialité & Sécurité")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.orange.opacity(0.4), Color.orange.opacity(0.25)],
                                            startPoint: .topLeading, endPoint: .bottomTrailing
                                        )
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                                            .strokeBorder(Color.orange.opacity(0.3), lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(.plain)

                        // Polling indicator — only shown while actively waiting
                        if hotkeyManager.accessibilityPollTask != nil {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .scaleEffect(0.55)
                                Text("En attente de votre autorisation…")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.white.opacity(0.3))
                            }
                        }
                    }
                    .frame(minHeight: 44)
                }
            }
        }
        .onAppear {
            hotkeyManager.checkAccessibilityPermission()
            if hotkeyManager.hasAccessibilityPermission {
                // Permission already granted — make sure the listener is running.
                hotkeyManager.startListening()
            } else {
                hotkeyManager.startPollingAccessibility()
            }
        }
        .onDisappear {
            // Stop polling only if permission was not yet granted
            if !hotkeyManager.hasAccessibilityPermission {
                hotkeyManager.stopPollingAccessibility()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isGranted)
    }
}

// MARK: - Mode row

private struct ModeRow: View {
    let mode: HotKeyMode
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .strokeBorder(
                            isSelected ? Color.accentColor : Color.white.opacity(0.2),
                            lineWidth: 1.5
                        )
                        .frame(width: 18, height: 18)
                    if isSelected {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 10, height: 10)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isSelected ? .white : .white.opacity(0.6))
                    Text(mode == .pushToTalk
                         ? "Maintenez la touche — relâchez pour transcrire"
                         : "Un appui pour démarrer, un appui pour arrêter")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.35))
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - HotKey Recorder

struct HotKeyRecorder: View {
    @Binding var hotKey: HotKey
    @State private var isRecording = false
    @State private var localMonitor: Any?
    @State private var globalMonitor: Any?
    @State private var flagsMonitor: Any?

    var body: some View {
        Button(action: toggleRecording) {
            HStack(spacing: 8) {
                if isRecording {
                    Circle()
                        .fill(.red)
                        .frame(width: 7, height: 7)
                        .opacity(0.9)
                    Text("Appuyez sur une touche…")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                } else {
                    Text(hotKey.displayString)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                    Image(systemName: "pencil")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isRecording
                          ? Color.red.opacity(0.12)
                          : Color.white.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(
                                isRecording ? Color.red.opacity(0.4) : Color.white.opacity(0.15),
                                lineWidth: 1
                            )
                    )
            )
            .animation(.easeInOut(duration: 0.15), value: isRecording)
        }
        .buttonStyle(.plain)
        .onDisappear { stopRecording() }
    }

    private func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        isRecording = true

        // Local monitor: captures regular key presses
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Escape cancels
                stopRecording()
                return nil
            }
            captureKey(keyCode: Int(event.keyCode), nsFlags: event.modifierFlags)
            return nil
        }

        // Flags monitor: captures modifier-only keys (Option, Cmd, Shift, Ctrl)
        // This fires when a modifier key is pressed/released.
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            let kc = Int(event.keyCode)
            let modifierOnlyCodes: Set<Int> = [54, 55, 56, 57, 58, 59, 60, 61, 62]
            guard modifierOnlyCodes.contains(kc) else { return event }

            // Detect key-down phase: flags contain the key's own flag
            let flags = event.modifierFlags
            let isKeyDown: Bool
            switch kc {
            case 58, 61: isKeyDown = flags.contains(.option)
            case 54, 55: isKeyDown = flags.contains(.command)
            case 56, 60: isKeyDown = flags.contains(.shift)
            case 57:     isKeyDown = flags.contains(.capsLock)
            case 59, 62: isKeyDown = flags.contains(.control)
            default:     isKeyDown = false
            }

            if isKeyDown {
                // For modifier-only hotkeys, store with NO extra modifiers
                // (the modifier IS the key, not an additional modifier)
                hotKey = HotKey(keyCode: kc, modifiers: 0)
                stopRecording()
            }
            return nil
        }
    }

    private func captureKey(keyCode: Int, nsFlags: NSEvent.ModifierFlags) {
        let relevantNS: NSEvent.ModifierFlags = [.control, .option, .shift, .command]
        let maskedNS = nsFlags.intersection(relevantNS)
        var cgRaw: UInt64 = 0
        if maskedNS.contains(.control) { cgRaw |= CGEventFlags.maskControl.rawValue }
        if maskedNS.contains(.option)  { cgRaw |= CGEventFlags.maskAlternate.rawValue }
        if maskedNS.contains(.shift)   { cgRaw |= CGEventFlags.maskShift.rawValue }
        if maskedNS.contains(.command) { cgRaw |= CGEventFlags.maskCommand.rawValue }
        hotKey = HotKey(keyCode: keyCode, modifiers: Int(cgRaw))
        stopRecording()
    }

    private func stopRecording() {
        isRecording = false
        if let m = localMonitor  { NSEvent.removeMonitor(m); localMonitor = nil }
        if let m = flagsMonitor  { NSEvent.removeMonitor(m); flagsMonitor = nil }
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
    }
}
