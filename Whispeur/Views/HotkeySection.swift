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
            SettingsCard {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(icon: "hand.raised.fill", title: "Permissions")

                    HStack {
                        Image(systemName: hotkeyManager.hasAccessibilityPermission
                              ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(hotkeyManager.hasAccessibilityPermission
                                             ? .green : .orange)
                        Text("Accessibilité")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.8))
                        Spacer()
                        if !hotkeyManager.hasAccessibilityPermission {
                            Button("Ouvrir les réglages") {
                                hotkeyManager.openAccessibilityPreferences()
                            }
                            .font(.system(size: 11))
                            .buttonStyle(.plain)
                            .foregroundStyle(.blue.opacity(0.8))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                Capsule().fill(Color.blue.opacity(0.1))
                                    .overlay(Capsule().strokeBorder(Color.blue.opacity(0.2), lineWidth: 1))
                            )
                        }
                    }
                    .frame(minHeight: 36)
                }
            }
        }
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
    @State private var monitor: Any?

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
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            // Escape cancels without saving.
            if event.keyCode == 53 {
                stopRecording()
                return nil
            }
            let relevantNS: NSEvent.ModifierFlags = [.control, .option, .shift, .command]
            let maskedNS = event.modifierFlags.intersection(relevantNS)
            // Convert NSEvent.ModifierFlags → CGEventFlags raw value for storage.
            var cgRaw: UInt64 = 0
            if maskedNS.contains(.control) { cgRaw |= CGEventFlags.maskControl.rawValue }
            if maskedNS.contains(.option)  { cgRaw |= CGEventFlags.maskAlternate.rawValue }
            if maskedNS.contains(.shift)   { cgRaw |= CGEventFlags.maskShift.rawValue }
            if maskedNS.contains(.command) { cgRaw |= CGEventFlags.maskCommand.rawValue }

            hotKey = HotKey(keyCode: Int(event.keyCode), modifiers: Int(cgRaw))
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }
}
