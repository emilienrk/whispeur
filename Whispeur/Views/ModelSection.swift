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
    @State private var expandedFamilies: Set<String> = []

    private let families = WhisperModelDescriptor.families

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

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
            }
            .padding(20)

            // Model list, folded by family
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(families) { family in
                        FamilyGroup(
                            family: family,
                            isExpanded: expandedFamilies.contains(family.name),
                            states: family.variants.map { manager.state(for: $0) },
                            selectedFilename: settings.selectedModelFilename,
                            onToggleExpanded: { toggleExpanded(family.name) },
                            row: { variant in row(for: variant) }
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .onAppear {
            manager.refreshInstalled()
            expandFamiliesInUse()
        }
    }

    // MARK: - Row construction

    private func row(for model: WhisperModelDescriptor) -> ModelRow {
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

    // MARK: - Expansion

    private func toggleExpanded(_ family: String) {
        if expandedFamilies.contains(family) {
            expandedFamilies.remove(family)
        } else {
            expandedFamilies.insert(family)
        }
    }

    /// Opens the families the user already has something in, so what's installed
    /// is visible without hunting through collapsed rows.
    private func expandFamiliesInUse() {
        expandedFamilies = Set(
            families
                .filter { $0.variants.contains { manager.isInstalled($0) } }
                .map(\.name)
        )
    }
}

// MARK: - Family group

private struct FamilyGroup<Row: View>: View {
    let family: WhisperModelFamily
    let isExpanded: Bool
    let states: [ModelDownloadState]
    let selectedFilename: String
    let onToggleExpanded: () -> Void
    @ViewBuilder let row: (WhisperModelDescriptor) -> Row

    private var installedCount: Int {
        states.filter { $0 == .done }.count
    }

    private var activeVariant: WhisperModelDescriptor? {
        family.variants.first { $0.filename == selectedFilename }
    }

    private var isBusy: Bool {
        states.contains {
            if case .downloading = $0 { return true }
            if case .installing = $0 { return true }
            return false
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            Button(action: onToggleExpanded) {
                HStack(spacing: 10) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.35))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))

                    Text(family.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(installedCount > 0 ? 1 : 0.7))

                    Spacer()

                    summary
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 6) {
                    ForEach(family.variants) { variant in
                        row(variant)
                    }
                }
                .padding(.leading, 20)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.03))
        )
        .animation(.easeInOut(duration: 0.18), value: isExpanded)
    }

    @ViewBuilder
    private var summary: some View {
        if let active = activeVariant {
            HStack(spacing: 6) {
                Text(active.quantization)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.35))
                Text("Actif")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
        } else if isBusy {
            ProgressView().scaleEffect(0.5).frame(width: 16, height: 16)
        } else if installedCount > 0 {
            Text(installedCount > 1 ? "\(installedCount) installés" : "1 installé")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
        } else {
            Text(family.variants.count > 1 ? "\(family.variants.count) variantes" : "1 variante")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.25))
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

    /// `.done` is the single source of truth: ModelManager derives it from its
    /// observable on-disk index, so the row reacts to install and delete alike.
    private var isDownloaded: Bool { downloadState == .done }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {

                // Selection checkbox (only when downloaded)
                selectionIndicator

                // Precision + size — the family header already carries the name
                HStack(spacing: 6) {
                    Text(model.quantization)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(isDownloaded ? .white : .white.opacity(0.45))
                    if model.isEnglishOnly {
                        Text("EN")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white.opacity(0.5))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.white.opacity(0.1)))
                    }
                    Text(model.fileSize)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.3))
                }

                Spacer()

                // Favorite button (only when downloaded)
                if isDownloaded {
                    Button(action: onToggleFavorite) {
                        Image(systemName: isFavorite ? "star.fill" : "star")
                            .foregroundStyle(isFavorite ? .yellow : .white.opacity(canFavorite ? 0.25 : 0.1))
                    }
                    .buttonStyle(.borderless)
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
            Button(action: onDownload) {
                Label(LocalizedStringKey("Télécharger"), systemImage: "arrow.down.circle")
            }

        case .downloading(let progress):
            // Cancel button + percentage
            HStack(spacing: 8) {
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
                Button(role: .cancel, action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.3))
                }
                .buttonStyle(.borderless)
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
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Supprimer le modèle")
            }

        case .failed:
            Button(action: onDownload) {
                Label(LocalizedStringKey("Réessayer"), systemImage: "arrow.clockwise")
            }
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
