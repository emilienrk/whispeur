// SettingsView.swift
// Whispeur
//
// Main settings window: glassmorphism background, 3 sections.
// Header + tab picker are sticky (outside the ScrollView).
// A single ScrollView wraps all tab content.

import SwiftUI
import AppKit

// MARK: - Root SettingsView

struct SettingsView: View {
    @Bindable var settings: AppSettings
    let coordinator: RecordingCoordinator

    @State private var selectedTab: SettingsTab = .hotkey

    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // ── Sticky header ──────────────────────────────────────────
                header
                    .padding(.top, 12)

                // ── Sticky tab picker ──────────────────────────────────────
                tabPicker
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)

                Divider().opacity(0.1)

                // ── Single scrollable area ─────────────────────────────────
                ScrollView(.vertical, showsIndicators: false) {
                    VStack {
                        switch selectedTab {
                        case .hotkey:
                            HotkeySection(
                                settings: settings,
                                hotkeyManager: coordinator.hotkeyManager
                            )
                        case .model:
                            ModelSection(settings: settings, coordinator: coordinator)
                        case .language:
                            LanguageSection(settings: settings)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 14)
                    .padding(.bottom, 16)
                }

                // ── Sticky footer ──────────────────────────────────────────
                Divider().opacity(0.15)
                footer
            }
        }
        .frame(width: 520, height: 540)
        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color(white: 0.28), Color(white: 0.18)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 44, height: 44)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                    )
                Image(systemName: micIcon(for: coordinator.pipelineState))
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(micColor(for: coordinator.pipelineState))
                    .animation(.spring(duration: 0.3), value: coordinator.pipelineState)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Whispeur")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                Text(statusLabel(for: coordinator.pipelineState))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                    .animation(.easeInOut, value: coordinator.pipelineState)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Tab picker

    private var tabPicker: some View {
        HStack(spacing: 0) {
            ForEach(SettingsTab.allCases) { tab in
                Button {
                    withAnimation(.spring(duration: 0.25)) { selectedTab = tab }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 12, weight: .medium))
                        Text(tab.label)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(selectedTab == tab ? Color.white.opacity(0.14) : Color.clear)
                    )
                    .foregroundStyle(selectedTab == tab ? .white : .white.opacity(0.45))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.white.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Circle()
                .fill(micColor(for: coordinator.pipelineState))
                .frame(width: 7, height: 7)
                .shadow(color: micColor(for: coordinator.pipelineState).opacity(0.8), radius: 4)
            Text(statusLabel(for: coordinator.pipelineState))
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
            Spacer()
            Text("v0.1.0")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.2))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    // MARK: - Helpers

    private func micIcon(for state: PipelineState) -> String {
        switch state {
        case .idle:         return "mic"
        case .loadingModel: return "waveform.circle"
        case .recording:    return "mic.fill"
        case .transcribing: return "waveform"
        case .pasting:      return "doc.on.clipboard.fill"
        case .error:        return "exclamationmark.triangle.fill"
        }
    }

    private func micColor(for state: PipelineState) -> Color {
        switch state {
        case .idle:         return .white.opacity(0.6)
        case .loadingModel: return .orange
        case .recording:    return .red
        case .transcribing: return .blue
        case .pasting:      return .green
        case .error:        return .orange
        }
    }

    private func statusLabel(for state: PipelineState) -> String {
        switch state {
        case .idle:         return "Prêt"
        case .loadingModel: return "Chargement du modèle…"
        case .recording:    return "Enregistrement en cours…"
        case .transcribing: return "Transcription…"
        case .pasting:      return "Collage du texte…"
        case .error(let m): return "Erreur : \(m)"
        }
    }
}

// MARK: - Tab enum

enum SettingsTab: String, CaseIterable, Identifiable {
    case hotkey, model, language
    var id: String { rawValue }

    var label: String {
        switch self {
        case .hotkey:    return "Raccourci"
        case .model:     return "Modèle"
        case .language:  return "Langue"
        }
    }
    var icon: String {
        switch self {
        case .hotkey:    return "keyboard"
        case .model:     return "cube.box.fill"
        case .language:  return "globe"
        }
    }
}

// MARK: - NSVisualEffectView wrapper

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blendingMode
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
        v.blendingMode = blendingMode
    }
}
