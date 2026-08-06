// OnboardingView.swift
// Whispeur
//
// First-launch setup: one page per OnboardingFlow step.
// Accessibility trust is re-read on every appearance because the user grants it
// in System Settings, outside the app — nothing notifies us.

import SwiftUI
import AppKit
import ApplicationServices

struct OnboardingView: View {
    let services: ServicesContainer
    let onFinish: () -> Void

    @State private var flow: OnboardingFlow
    @State private var isAXTrusted = false

    init(services: ServicesContainer, onFinish: @escaping () -> Void) {
        self.services = services
        self.onFinish = onFinish
        _flow = State(
            initialValue: OnboardingFlow(
                requirements: SystemOnboardingRequirements(
                    micManager: services.micPermManager,
                    settings: services.settings
                )
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            page
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(28)

            Divider().opacity(0.12)

            footer
                .padding(16)
        }
        .frame(width: 520, height: 460)
        .preferredColorScheme(.dark)
        .onAppear { isAXTrusted = AXIsProcessTrusted() }
    }

    // MARK: - Pages

    @ViewBuilder
    private var page: some View {
        switch flow.step {
        case .welcome:       welcomePage
        case .microphone:    microphonePage
        case .accessibility: accessibilityPage
        case .model:         modelPage
        case .hotkey:        hotkeyPage
        case .done:          donePage
        }
    }

    private var welcomePage: some View {
        pageLayout(
            icon: "mic.fill",
            title: "Bienvenue dans Whispeur",
            subtitle: "Dictez dans n'importe quelle application. Votre voix est transcrite sur votre Mac, sans jamais partir sur Internet."
        ) {
            EmptyView()
        }
    }

    private var microphonePage: some View {
        pageLayout(
            icon: "waveform",
            title: "Accès au microphone",
            subtitle: "Whispeur a besoin du micro pour capturer votre voix. Sans cette autorisation, la dictée ne peut pas fonctionner."
        ) {
            VStack(spacing: 10) {
                if services.micPermManager.canRecord {
                    statusLine(granted: true, text: "Microphone autorisé")
                } else {
                    Button("Autoriser le microphone") {
                        Task { await services.micPermManager.requestIfNeeded() }
                    }
                    .buttonStyle(.borderedProminent)

                    if services.micPermManager.status == .denied {
                        Button("Ouvrir les Réglages Système") {
                            services.micPermManager.openSystemPreferences()
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.white.opacity(0.6))
                    }
                }
            }
        }
    }

    private var accessibilityPage: some View {
        pageLayout(
            icon: "hand.tap.fill",
            title: "Collage automatique",
            subtitle: "Avec l'autorisation d'Accessibilité, Whispeur colle le texte directement dans l'application active. Sans elle, le texte est copié dans le presse-papier — vous collez avec ⌘V."
        ) {
            VStack(spacing: 10) {
                if isAXTrusted {
                    statusLine(granted: true, text: "Accessibilité autorisée")
                } else {
                    Button("Ouvrir les Réglages Système") {
                        openAccessibilitySettings()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Vérifier à nouveau") {
                        isAXTrusted = AXIsProcessTrusted()
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
    }

    private var modelPage: some View {
        pageLayout(
            icon: "cube.box.fill",
            title: "Modèle de transcription",
            subtitle: "Le modèle tourne sur votre Mac. Le téléchargement n'a lieu qu'une fois."
        ) {
            VStack(spacing: 12) {
                modelRow(WhisperModelDescriptor.onboardingDefault, recommended: true)
                modelRow(WhisperModelDescriptor.onboardingLight, recommended: false)
            }
        }
    }

    private var hotkeyPage: some View {
        pageLayout(
            icon: "keyboard",
            title: "Essayez",
            subtitle: "Maintenez la touche 🎤 de votre clavier, dites une phrase, puis relâchez. Le texte apparaît ci-dessous."
        ) {
            VStack(spacing: 10) {
                Text(services.coordinator.lastTranscription.isEmpty
                     ? "En attente de votre première dictée…"
                     : services.coordinator.lastTranscription)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(services.coordinator.lastTranscription.isEmpty ? 0.3 : 0.85))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                    )

                Text("La dictée d'Apple utilise la même touche et joue ses propres bips. Désactivez-la pour laisser la touche à Whispeur.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 360)

                Button("Ouvrir les réglages de dictée") {
                    openDictationSettings()
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    private var donePage: some View {
        pageLayout(
            icon: "checkmark.circle.fill",
            title: "Tout est prêt",
            subtitle: "Whispeur vit dans la barre de menus. Retrouvez-y vos modèles, votre historique et vos réglages."
        ) {
            EmptyView()
        }
    }

    // MARK: - Building blocks

    private func pageLayout<Content: View>(
        icon: String,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 14) {
            Spacer()

            Image(systemName: icon)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.white.opacity(0.75))

            Text(title)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))

            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 380)

            content()
                .padding(.top, 4)

            Spacer()
        }
    }

    private func statusLine(granted: Bool, text: LocalizedStringKey) -> some View {
        HStack(spacing: 6) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(granted ? Color.green : Color.white.opacity(0.3))
            Text(text)
                .foregroundStyle(.white.opacity(0.8))
        }
        .font(.system(size: 12, weight: .medium))
    }

    private func modelRow(_ model: WhisperModelDescriptor, recommended: Bool) -> some View {
        let state = ModelManager.shared.state(for: model)

        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(model.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                    if recommended {
                        Text("recommandé")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
                Text(model.sizeInfo)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.35))
            }

            Spacer()

            switch state {
            case .done:
                Button("Utiliser") { select(model) }
                    .buttonStyle(.borderedProminent)
            case .downloading(let progress):
                ProgressView(value: progress)
                    .frame(width: 90)
            case .installing:
                ProgressView().controlSize(.small)
            case .failed(let message):
                Text(message)
                    .font(.system(size: 10))
                    .foregroundStyle(.red.opacity(0.8))
            case .idle:
                Button("Télécharger") {
                    ModelManager.shared.download(model)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if flow.step != .welcome && flow.step != .done {
                Button("Retour") { flow.back() }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.white.opacity(0.5))
            }

            Spacer()

            if flow.step == .done {
                Button("Terminer") { onFinish() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Continuer") { flow.advance() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!flow.canAdvance)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: - Actions

    private func select(_ model: WhisperModelDescriptor) {
        services.settings.selectedModelFilename = model.filename
        services.coordinator.modelURL = model.localURL
    }

    /// Apple's dictation is bound to the same 🎤 key and answers it with its own
    /// start/stop chimes — nothing Whispeur can silence from its side.
    private func openDictationSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private func openAccessibilitySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}
