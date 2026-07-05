// GeneralSection.swift
// Whispeur
//
// Settings tab: general UX preferences.

import SwiftUI

struct GeneralSection: View {
    @Bindable var settings: AppSettings
    let hotkeyManager: HotkeyManager

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {

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
                            ),
                            hotkeyManager: hotkeyManager
                        )
                    }

                    Text("Fonctionne même quand Whispeur est en arrière-plan. La touche choisie est interceptée avant macOS : binder la touche Dictée remplace la dictée Apple.")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }

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

            // MARK: - Dictation behavior
            SettingsCard {
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(icon: "text.bubble.fill", title: "Comportement")

                    SettingsToggleRow(
                        icon: "doc.on.clipboard.fill",
                        label: "Coller automatiquement",
                        description: "Insère le texte directement dans l'app active après la transcription.",
                        isOn: $settings.autoPasteEnabled
                    )

                    Divider().opacity(0.08)

                    SettingsToggleRow(
                        icon: "speaker.wave.2.fill",
                        label: "Son de confirmation",
                        description: "Émet un son bref quand la transcription est prête.",
                        isOn: $settings.confirmationSoundEnabled
                    )
                }
            }

            // MARK: - System
            SettingsCard {
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(icon: "gearshape.2.fill", title: "Système")

                    SettingsToggleRow(
                        icon: "arrow.up.circle.fill",
                        label: "Démarrer au login",
                        description: "Lance Whispeur automatiquement au démarrage de macOS.",
                        isOn: $settings.launchAtLogin
                    )
                }
            }

            // MARK: - Interface
            SettingsCard {
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(icon: "character.bubble.fill", title: "Interface")

                    HStack {
                        Text("Langue de l'application")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.9))
                        Spacer()
                        Picker("", selection: $settings.uiLanguage) {
                            Text(verbatim: "Français").tag("fr")
                            Text(verbatim: "English").tag("en")
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 120)
                    }

                    Text("Le changement de langue nécessite le redémarrage de l'application.")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
        }
    }
}

// MARK: - Reusable toggle row

struct SettingsToggleRow: View {
    let icon: String
    let label: String
    let description: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 20)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.35))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .tint(Color.accentColor)
                .scaleEffect(0.85)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .contentShape(Rectangle())
        .onTapGesture { isOn.toggle() }
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
    let hotkeyManager: HotkeyManager
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
        }
        .onDisappear { stopRecording() }
    }

    private func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        isRecording = true
        NSApp.activate()

        // Voie principale : capture via le CGEventTap du HotkeyManager.
        // C'est la seule source qui voit les touches spéciales (🎤 dictée,
        // Mission Control…) et qui les consomme avant que macOS ne réagisse.
        if hotkeyManager.beginHotKeyCapture({ captured in
            if let captured { hotKey = captured }
            isRecording = false
        }) {
            return
        }

        // Repli sans permission d'accessibilité : moniteurs NSEvent
        // (ne voit pas les touches spéciales comme 🎤).
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                stopRecording()
                return nil
            }
            captureKey(keyCode: Int(event.keyCode), nsFlags: event.modifierFlags)
            return nil
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            DispatchQueue.main.async {
                guard self.isRecording else { return }
                if event.keyCode == 53 {
                    self.stopRecording()
                    return
                }
                self.captureKey(keyCode: Int(event.keyCode), nsFlags: event.modifierFlags)
            }
        }

        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            let kc = Int(event.keyCode)
            let modifierOnlyCodes: Set<Int> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
            guard modifierOnlyCodes.contains(kc) else { return event }

            let flags = event.modifierFlags
            let isKeyDown: Bool
            switch kc {
            case 58, 61: isKeyDown = flags.contains(.option)
            case 54, 55: isKeyDown = flags.contains(.command)
            case 56, 60: isKeyDown = flags.contains(.shift)
            case 57:     isKeyDown = flags.contains(.capsLock)
            case 59, 62: isKeyDown = flags.contains(.control)
            case 63:     isKeyDown = flags.contains(.function)
            default:     isKeyDown = false
            }

            if !isKeyDown {
                guard self.isRecording else { return event }
                hotKey = HotKey(keyCode: kc, modifiers: 0)
                stopRecording()
            }
            return event
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
        hotkeyManager.cancelHotKeyCapture()
        if let m = localMonitor  { NSEvent.removeMonitor(m); localMonitor = nil }
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        if let m = flagsMonitor  { NSEvent.removeMonitor(m); flagsMonitor = nil }
    }
}
