// ModelSection.swift
// Whispeur
//
// Settings tab: model selection + download with progress bar.
// The ScrollView is now managed by the parent SettingsView — no inner scroll here.

import SwiftUI

struct ModelSection: View {
    @Bindable var settings: AppSettings
    let coordinator: RecordingCoordinator

    @State private var manager = ModelManager.shared

    private let catalog = WhisperModelDescriptor.catalog

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            SettingsCard {
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(icon: "cube.box.fill", title: "Modèle Whisper")
                    HStack(spacing: 6) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.yellow.opacity(0.7))
                        Text("Marquez jusqu'à \(AppSettings.maxFavorites) modèles en favori pour un accès rapide depuis la barre de menu.")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                    Text("Stockés dans ~/Library/Application Support/Whispeur/Models/")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.2))
                }
            }

            // Model list — no inner ScrollView, parent handles scrolling
            LazyVStack(spacing: 6) {
                ForEach(catalog) { model in
                    ModelRow(
                        model: model,
                        downloadState: manager.state(for: model),
                        isSelected: settings.selectedModelFilename == model.filename,
                        isFavorite: settings.isFavorite(filename: model.filename),
                        canFavorite: settings.favoritedModelFilenames.count < AppSettings.maxFavorites
                                  || settings.isFavorite(filename: model.filename),
                        onSelect: {
                            settings.selectedModelFilename = model.filename
                            coordinator.modelURL = model.localURL
                        },
                        onToggleFavorite: {
                            settings.toggleFavorite(filename: model.filename)
                        },
                        onDownload: { manager.download(model) },
                        onCancel:   { manager.cancel(model) },
                        onDelete:   {
                            if settings.selectedModelFilename == model.filename {
                                settings.selectedModelFilename = ""
                                coordinator.modelURL = nil
                            }
                            // Also remove from favorites if deleted
                            if settings.isFavorite(filename: model.filename) {
                                settings.toggleFavorite(filename: model.filename)
                            }
                            manager.delete(model)
                        }
                    )
                }
            }
            .padding(.bottom, 6)
        }
    }
}

// MARK: - Model row

private struct ModelRow: View {
    let model: WhisperModelDescriptor
    let downloadState: ModelDownloadState
    let isSelected: Bool
    let isFavorite: Bool
    let canFavorite: Bool
    let onSelect:        () -> Void
    let onToggleFavorite: () -> Void
    let onDownload:      () -> Void
    let onCancel:        () -> Void
    let onDelete:        () -> Void

    private var isDownloaded: Bool {
        if case .done = downloadState { return true }
        return model.isDownloaded && downloadState == .idle
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {

                // Selection checkbox (only when downloaded)
                selectionIndicator

                // Name + size
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(model.name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(isDownloaded ? .white : .white.opacity(0.45))
                        if model.isEnglishOnly {
                            Text("EN")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white.opacity(0.5))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.white.opacity(0.1)))
                        }
                    }
                    Text(model.sizeInfo)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.3))
                }

                Spacer()

                // Favorite button (only when downloaded)
                if isDownloaded {
                    Button(action: onToggleFavorite) {
                        Image(systemName: isFavorite ? "star.fill" : "star")
                            .font(.system(size: 13))
                            .foregroundStyle(isFavorite ? .yellow : .white.opacity(canFavorite ? 0.25 : 0.1))
                    }
                    .buttonStyle(.plain)
                    .help(isFavorite ? "Retirer des favoris" : canFavorite ? "Ajouter aux favoris" : "Maximum \(AppSettings.maxFavorites) favoris")
                    .disabled(!canFavorite && !isFavorite)
                    .animation(.spring(duration: 0.25), value: isFavorite)
                }

                // Action area (right side)
                trailingAction
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            // Inline progress bar
            if case .downloading(let progress) = downloadState {
                DownloadProgressBar(progress: progress)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.09) : Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            isSelected ? Color.accentColor.opacity(0.35) : Color.white.opacity(0.07),
                            lineWidth: 1
                        )
                )
        )
        .animation(.easeInOut(duration: 0.2), value: downloadState)
        .contentShape(Rectangle())
        .onTapGesture { if isDownloaded { onSelect() } }
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var selectionIndicator: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.25) : Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(
                            isSelected ? Color.accentColor : Color.white.opacity(0.12),
                            lineWidth: 1
                        )
                )
                .frame(width: 20, height: 20)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .opacity(isDownloaded ? 1 : 0.4)
    }

    @ViewBuilder
    private var trailingAction: some View {
        switch downloadState {
        case .idle:
            if model.isDownloaded {
                // Downloaded but not active: show status + delete
                HStack(spacing: 8) {
                    Text(isSelected ? "Actif" : "Installé")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isSelected ? Color.accentColor : .white.opacity(0.4))
                    if !isSelected {
                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.25))
                        }
                        .buttonStyle(.plain)
                        .help("Supprimer le modèle")
                    }
                }
            } else {
                // Not downloaded: download button
                Button(action: onDownload) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 13))
                        Text("Télécharger")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.07))
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                    )
                }
                .buttonStyle(.plain)
            }

        case .downloading(let progress):
            // Cancel button + percentage
            HStack(spacing: 8) {
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.3))
                }
                .buttonStyle(.plain)
                .help("Annuler")
            }

        case .installing:
            HStack(spacing: 6) {
                ProgressView()
                    .scaleEffect(0.65)
                Text("Installation…")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
            }

        case .done:
            HStack(spacing: 8) {
                Text(isSelected ? "Actif" : "Installé")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isSelected ? Color.accentColor : .white.opacity(0.4))
                if !isSelected {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.25))
                    }
                    .buttonStyle(.plain)
                    .help("Supprimer le modèle")
                }
            }

        case .failed:
            Button(action: onDownload) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                    Text("Réessayer")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(.orange.opacity(0.8))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(Color.orange.opacity(0.08))
                        .overlay(Capsule().strokeBorder(Color.orange.opacity(0.2), lineWidth: 1))
                )
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Progress bar

private struct DownloadProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Track
                Capsule()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 4)
                // Fill
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(8, geo.size.width * progress), height: 4)
                    .animation(.easeInOut(duration: 0.3), value: progress)
            }
        }
        .frame(height: 4)
    }
}
