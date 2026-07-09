// EngineSection.swift
// Whispeur
//
// Settings tab: advanced Whisper engine parameters.

import SwiftUI

struct EngineSection: View {
    @Bindable var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {

            // MARK: - Decoding strategy
            SettingsCard {
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(icon: "waveform.path.ecg", title: "Stratégie de décodage")

                    VStack(spacing: 4) {
                        DecodingModeRow(
                            title: "Greedy (rapide)",
                            description: "Choisit toujours le token le plus probable. Optimal pour la dictée en temps réel.",
                            icon: "bolt.fill",
                            isSelected: !settings.useBeamSearch,
                            action: { settings.useBeamSearch = false }
                        )
                        DecodingModeRow(
                            title: "Beam Search (précis)",
                            description: "Explore plusieurs chemins. Meilleur pour les noms propres, termes techniques et langues mixtes.",
                            icon: "sparkles",
                            isSelected: settings.useBeamSearch,
                            action: { settings.useBeamSearch = true }
                        )
                    }

                    if settings.useBeamSearch {
                        Divider().opacity(0.08)

                        HStack {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.5))
                            Text("Taille du beam")
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.7))
                            Spacer()
                            HStack(spacing: 8) {
                                Text("\(settings.beamSize)")
                                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.white)
                                    .frame(width: 20, alignment: .center)

                                Stepper("", value: $settings.beamSize, in: 1...10)
                                    .labelsHidden()
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .animation(.spring(duration: 0.25), value: settings.useBeamSearch)
            }

            // MARK: - Quality sliders
            SettingsCard {
                VStack(alignment: .leading, spacing: 16) {
                    SectionHeader(icon: "dial.medium.fill", title: "Qualité & Précision")

                    // Temperature
                    EngineSliderRow(
                        icon: "thermometer.medium",
                        label: "Température",
                        value: $settings.temperature,
                        range: 0.0...1.0,
                        lowLabel: "Déterministe",
                        highLabel: "Créatif",
                        description: "À 0, la transcription est reproductible. Plus haute = plus de variété, mais aussi plus d'erreurs.",
                        step: 0.05,
                        format: { String(format: "%.2f", $0) }
                    )

                    Divider().opacity(0.08)

                    // No speech threshold
                    EngineSliderRow(
                        icon: "waveform.slash",
                        label: "Seuil de silence",
                        value: $settings.noSpeechThreshold,
                        range: 0.0...1.0,
                        lowLabel: "Sensible",
                        highLabel: "Strict",
                        description: "Si la proba de silence dépasse ce seuil, le segment est ignoré. Augmenter réduit les hallucinations.",
                        step: 0.05,
                        format: { String(format: "%.2f", $0) }
                    )
                }
            }

            // MARK: - Initial prompt
            SettingsCard {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(icon: "text.quote", title: "Prompt initial")

                    TextEditor(text: $settings.initialPrompt)
                        .font(.system(size: 13))
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .frame(height: 70)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                                )
                        )

                    Text("Donné au modèle comme contexte avant chaque dictée : vocabulaire spécifique, noms propres, style de ponctuation. Vide = désactivé.")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.3))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // MARK: - VAD
            SettingsCard {
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(icon: "waveform.badge.mic", title: "Détection de voix (VAD)")
                    VADToggleRow(settings: settings)
                }
            }

            // MARK: - Context & hardware
            SettingsCard {
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(icon: "cpu.fill", title: "Contexte & Matériel")

                    SettingsToggleRow(
                        icon: "text.append",
                        label: "Contexte précédent",
                        description: "Conditionne la transcription sur les segments précédents. Améliore la cohérence sur les longues sessions.",
                        isOn: $settings.conditionOnPreviousText
                    )

                    Divider().opacity(0.08)

                    SettingsToggleRow(
                        icon: "memorychip.fill",
                        label: "Accélération GPU (Metal)",
                        description: "Utilise le GPU Apple Silicon pour accélérer la transcription. Désactiver libère le GPU pour d'autres apps.",
                        isOn: $settings.useGPU
                    )
                    
                    Divider().opacity(0.08)

                    EngineSliderRow(
                        icon: "timer",
                        label: "Délai de déchargement",
                        value: $settings.modelUnloadDelay,
                        range: 0.0...300.0,
                        lowLabel: "0s",
                        highLabel: "5 min",
                        description: "Temps avant de décharger le modèle de la RAM après une dictée. 0s = immédiat.",
                        format: { val in
                            val == 0 ? "0s" : (val < 60 ? "\(Int(val))s" : "\(Int(val)/60)m\(Int(val)%60 > 0 ? " \(Int(val)%60)s" : "")")
                        }
                    )

                    Text("Certains changements prennent effet au prochain enregistrement.")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.25))
                }
            }
        }
    }
}

// MARK: - Decoding mode row

private struct DecodingModeRow: View {
    let title: String
    let description: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
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

                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isSelected ? Color.accentColor : .white.opacity(0.4))
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isSelected ? .white : .white.opacity(0.6))
                    Text(description)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.35))
                        .fixedSize(horizontal: false, vertical: true)
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

// MARK: - VAD toggle row (avec téléchargement du modèle Silero)

private struct VADToggleRow: View {
    @Bindable var settings: AppSettings

    var body: some View {
        let model = WhisperModelDescriptor.vadSilero
        let state = ModelManager.shared.state(for: model)

        VStack(alignment: .leading, spacing: 8) {
            SettingsToggleRow(
                icon: "waveform.and.mic",
                label: "Filtre VAD (Silero)",
                description: "Ignore les passages sans parole avant la transcription. Réduit les hallucinations sur les silences.",
                isOn: Binding(
                    get: { settings.vadEnabled },
                    set: { enabled in
                        settings.vadEnabled = enabled
                        if enabled && !model.isDownloaded {
                            ModelManager.shared.download(model)
                        }
                    }
                )
            )

            if settings.vadEnabled {
                switch state {
                case .downloading(let progress):
                    HStack(spacing: 8) {
                        ProgressView(value: progress)
                            .frame(maxWidth: 160)
                        Text("Téléchargement du modèle VAD… \(Int(progress * 100)) %")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                case .installing:
                    Text("Installation…")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                case .failed(let message):
                    Text("Échec du téléchargement : \(message)")
                        .font(.system(size: 11))
                        .foregroundStyle(.red.opacity(0.8))
                case .idle:
                    Text("Modèle VAD manquant — désactivez puis réactivez pour relancer le téléchargement.")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange.opacity(0.8))
                case .done:
                    EmptyView()
                }
            }
        }
    }
}

// MARK: - Engine slider row

private struct EngineSliderRow: View {
    let icon: String
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let lowLabel: String
    let highLabel: String
    let description: String
    var step: Double? = nil
    let format: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 20)
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                Spacer()
                Text(format(value))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            if let step = step {
                Slider(value: $value, in: range, step: step)
                    .tint(Color.accentColor)
            } else {
                Slider(value: $value, in: range)
                    .tint(Color.accentColor)
            }

            HStack {
                Text(lowLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.25))
                Spacer()
                Text(highLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.25))
            }

            Text(description)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.3))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
