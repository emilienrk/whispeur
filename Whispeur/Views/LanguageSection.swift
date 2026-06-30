// LanguageSection.swift
// Whispeur
//
// Settings tab: transcription language picker.

import SwiftUI

struct LanguageSection: View {
    @Bindable var settings: AppSettings

    @State private var searchQuery: String = ""

    private var filteredLanguages: [WhisperLanguage] {
        if searchQuery.isEmpty { return WhisperLanguage.all }
        let q = searchQuery.lowercased()
        return WhisperLanguage.all.filter {
            $0.displayName.lowercased().contains(q) ||
            ($0.whisperCode ?? "").lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            SettingsCard {
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(icon: "globe", title: "Langue de transcription")

                    // Current selection
                    HStack {
                        Text("Langue active")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.7))
                        Spacer()
                        Text(settings.selectedLanguage.displayName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                    }

                    // Auto-detect note
                    if settings.languageCode == "auto" {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 11))
                                .foregroundStyle(.yellow.opacity(0.7))
                            Text("Whisper détecte automatiquement la langue parlée.")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }
                }
            }

            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.35))
                TextField("Rechercher une langue…", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                if !searchQuery.isEmpty {
                    Button { searchQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )

            // Language list
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(filteredLanguages) { lang in
                        LanguageRow(
                            language: lang,
                            isSelected: settings.languageCode == lang.id,
                            onSelect: { settings.selectedLanguage = lang }
                        )
                    }
                }
                .padding(.bottom, 8)
            }
            .frame(maxHeight: 220)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.04),
                        .init(color: .black, location: 0.96),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }
}

// MARK: - Language row

private struct LanguageRow: View {
    let language: WhisperLanguage
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 16)
                } else {
                    Spacer().frame(width: 16)
                }

                Text(language.displayName)
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.65))

                Spacer()

                if let code = language.whisperCode {
                    Text(code.uppercased())
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.25))
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10))
                        .foregroundStyle(.yellow.opacity(0.5))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(
                                isSelected ? Color.accentColor.opacity(0.3) : Color.clear,
                                lineWidth: 1
                            )
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.12), value: isSelected)
    }
}
