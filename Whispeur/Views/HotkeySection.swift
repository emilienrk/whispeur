// HotkeySection.swift
// Whispeur
//
// Settings tab: hotkey selection and recording mode.

import SwiftUI
import AppKit

struct HotkeySection: View {
    @Bindable var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            // MARK: - Recording mode
            SettingsCard {
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(icon: "record.circle", title: "Mode d'enregistrement")

                    VStack(spacing: 8) {
                        ForEach(HotKeyMode.allCases, id: \.self) { mode in
                            ModeRow(
                                mode: mode,
                                isSelected: settings.hotKeyMode == mode,
                                onSelect: { settings.hotKeyMode = mode }
                            )
                        }
                    }
                }
            }

            // MARK: - Hotkey display
            SettingsCard {
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(icon: "keyboard", title: "Raccourci clavier")

                    HStack {
                        Text("Touche active")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.7))
                        Spacer()
                        HotKeyBadge(hotKey: settings.currentHotKey)
                    }

                    Text("Le raccourci fonctionne même quand Whispeur est en arrière-plan.")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.35))
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
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - Hotkey badge

private struct HotKeyBadge: View {
    let hotKey: HotKey

    var body: some View {
        Text(hotKey.displayString)
            .font(.system(size: 13, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                    )
            )
    }
}
