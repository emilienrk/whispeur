// PermissionsSection.swift
// Whispeur
//
// Settings tab: microphone + accessibility permission status and guided actions.

import SwiftUI
import AppKit
import AVFoundation

// MARK: - PermissionsSection

struct PermissionsSection: View {
    @Bindable var micManager: MicrophonePermissionManager

    /// Refreshes AX trust status on appear and on button tap.
    @State private var isAXTrusted: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            micCard
            accessibilityCard
        }
        .onAppear { refreshAXStatus() }
    }

    // MARK: - Microphone card

    private var micCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(icon: "mic.fill", title: "Microphone")

                HStack(spacing: 10) {
                    // Status badge
                    HStack(spacing: 6) {
                        Circle()
                            .fill(micStatusColor)
                            .frame(width: 8, height: 8)
                            .shadow(color: micStatusColor.opacity(0.8), radius: 4)
                        Text(micStatusLabel)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    Spacer()
                    micActionButton
                }

                Text("Whispeur a besoin du microphone pour capturer votre voix et la transcrire localement.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.3))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var micActionButton: some View {
        switch micManager.status {
        case .undetermined:
            permissionButton(label: "Demander l'accès", icon: "hand.raised") {
                Task { await micManager.requestIfNeeded() }
            }
        case .denied, .restricted:
            permissionButton(label: "Ouvrir les Réglages", icon: "arrow.up.right.square") {
                micManager.openSystemPreferences()
            }
        case .granted:
            EmptyView()
        }
    }

    private var micStatusColor: Color {
        switch micManager.status {
        case .granted:      return .green
        case .undetermined: return .orange
        case .denied:       return .red
        case .restricted:   return .red
        }
    }

    private var micStatusLabel: String {
        switch micManager.status {
        case .granted:      return "Accès accordé"
        case .undetermined: return "Non déterminé"
        case .denied:       return "Accès refusé"
        case .restricted:   return "Accès restreint"
        }
    }

    // MARK: - Accessibility card

    private var accessibilityCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(icon: "lock.shield.fill", title: "Accessibilité")

                HStack(spacing: 10) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(isAXTrusted ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                            .shadow(color: (isAXTrusted ? Color.green : Color.orange).opacity(0.8), radius: 4)
                        Text(isAXTrusted ? "Accès accordé" : "Non accordé")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    Spacer()
                    if !isAXTrusted {
                        permissionButton(label: "Ouvrir les Réglages", icon: "arrow.up.right.square") {
                            openAXPreferences()
                            // Refresh after a short delay (user may grant while settings are open)
                            Task {
                                try? await Task.sleep(for: .seconds(2))
                                refreshAXStatus()
                            }
                        }
                    }
                }

                Text("Requise pour simuler Cmd+V et coller le texte transcrit dans l'application active.\nDans Réglages → Confidentialité & Sécurité → Accessibilité, activez Whispeur.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.3))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Helpers

    private func refreshAXStatus() {
        isAXTrusted = AXIsProcessTrusted()
    }

    private func openAXPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func permissionButton(label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(LocalizedStringKey(label), systemImage: icon)
        }
    }
}
