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
        case .welcome:        welcomePage
        case .microphone:     microphonePage
        case .accessibility:  accessibilityPage
        case .model:          modelPage
        case .engineOverview: engineOverviewPage
        case .engine:         enginePage
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

    /// Names the four levers before the next step touches two of them: a setting is
    /// only worth a switch once you know what it acts on. No control here on purpose.
    private var engineOverviewPage: some View {
        pageLayout(
            icon: nil,
            title: "Comment Whispeur transcrit",
            subtitle: "Votre voix est découpée, passée au modèle, puis recollée en texte — le tout sur votre Mac. Quatre choses décident du résultat."
        ) {
            VStack(spacing: 20) {
                transcriptionFlow
                engineLevers
            }
        }
    }

    private var transcriptionFlow: some View {
        HStack(spacing: 8) {
            flowStage(icon: "mic.fill", label: "Votre voix")
            flowArrow
            flowStage(icon: "cpu.fill", label: "Le modèle")
            flowArrow
            flowStage(icon: "text.alignleft", label: "Le texte")
        }
    }

    private func flowStage(icon: String, label: LocalizedStringKey) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .light))
                .foregroundStyle(.white.opacity(0.75))
                .frame(height: 22)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.45))
        }
        .frame(width: 78)
    }

    /// Padded down by the label height so the chevron sits level with the icons,
    /// not with the middle of the whole stage.
    private var flowArrow: some View {
        Image(systemName: "chevron.compact.right")
            .font(.system(size: 15, weight: .light))
            .foregroundStyle(.white.opacity(0.25))
            .padding(.bottom, 18)
    }

    private var engineLevers: some View {
        VStack(alignment: .leading, spacing: 10) {
            leverRow(
                icon: "cube.box.fill",
                text: "**Le modèle** — celui que vous venez de choisir. Le plus gros est le plus juste, et le plus lent."
            )
            leverRow(
                icon: "text.quote",
                text: "**Le vocabulaire** — quelques phrases d'exemple, et vos noms propres cessent d'être devinés."
            )
            leverRow(
                icon: "waveform.slash",
                text: "**Les silences** — filtrés, le modèle n'a plus de blanc où inventer du texte."
            )
            leverRow(
                icon: "bolt.fill",
                text: "**Le décodage** — au plus probable, ou en explorant plusieurs pistes quand la précision prime."
            )
        }
        .frame(maxWidth: 400)
    }

    private func leverRow(icon: String, text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
                .frame(width: 16)
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    /// Sits before the first dictation on purpose: what is set here is already in
    /// effect when the user tries the hotkey, so the step proves itself instead of
    /// describing itself — and the VAD model downloads while they read.
    ///
    /// Only the two settings whose default is inert are surfaced. Everything else
    /// in Réglages › Moteur ships with a value that suits dictation as-is, and a
    /// setup wizard is the wrong place to ask a question the user cannot yet judge.
    private var enginePage: some View {
        pageLayout(
            icon: "slider.horizontal.3",
            title: "Affiner la transcription",
            subtitle: "Sur les quatre leviers, deux sont livrés inactifs. Les poser maintenant, c'est autant de gagné dès votre premier essai."
        ) {
            VStack(spacing: 10) {
                onboardingCard {
                    VADToggleRow(settings: services.settings)
                }

                onboardingCard {
                    vocabularyPicker
                }

                Text("Stratégie de décodage, température, seuil de silence : dans Réglages › Moteur, le jour où vous voudrez creuser.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.35))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 380)
            }
        }
    }

    /// Presets only — the free-form editor stays in Settings. Picking from a list is
    /// a tutorial; facing an empty text field on first launch is a puzzle.
    private var vocabularyPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "text.quote")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 20)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Vocabulaire & style")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                    Text("Whisper n'obéit pas à des consignes : il imite ce qu'il lit. Donnez-lui un exemple, il en calque le vocabulaire et la ponctuation.")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.35))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Menu {
                    ForEach(PromptPreset.all) { preset in
                        Button {
                            append(preset)
                        } label: {
                            Text(preset.title)
                            Text(preset.subtitle)
                        }
                    }
                    if !services.settings.initialPrompt.isEmpty {
                        Divider()
                        Button("Vider", role: .destructive) {
                            services.settings.initialPrompt = ""
                        }
                    }
                } label: {
                    Label("Exemples", systemImage: "sparkles")
                        .font(.system(size: 12))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            if !services.settings.initialPrompt.isEmpty {
                Text(verbatim: services.settings.initialPrompt)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
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

    /// A nil icon is for the page whose own illustration stands in for it — the
    /// glyph would only compete with it for the little height the window has.
    private func pageLayout<Content: View>(
        icon: String?,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 14) {
            Spacer()

            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(.white.opacity(0.75))
            }

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

    private func onboardingCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
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

        return onboardingCard {
            HStack(spacing: 10) {
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
        }
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

    /// Same additive behaviour as the Settings field: combining a vocabulary preset
    /// with a style one is the intended use, so picking a second never wipes the first.
    private func append(_ preset: PromptPreset) {
        let current = services.settings.initialPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        services.settings.initialPrompt = current.isEmpty ? preset.text : current + "\n" + preset.text
    }

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
