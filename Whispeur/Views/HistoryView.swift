// HistoryView.swift
// Whispeur
//
// Displays the transcription history.

import SwiftUI

struct HistoryView: View {
    @Bindable var historyService: HistoryService
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            
            // Header
            SettingsCard {
                HStack {
                    SectionHeader(icon: "clock.fill", title: "Historique des transcriptions")
                    
                    Spacer()
                    
                    Button {
                        historyService.clearAll()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                            Text("Effacer")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(historyService.items.isEmpty ? .white.opacity(0.3) : .red)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(historyService.items.isEmpty ? Color.white.opacity(0.05) : Color.red.opacity(0.15))
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(historyService.items.isEmpty)
                }
            }
            
            // Content
            if historyService.items.isEmpty {
                SettingsCard {
                    VStack(spacing: 12) {
                        Image(systemName: "clock")
                            .font(.system(size: 32))
                            .foregroundStyle(.white.opacity(0.2))
                        Text("Aucune transcription récente.")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                }
            } else {
                VStack(spacing: 12) {
                    ForEach(historyService.items) { item in
                        SettingsCard {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .top) {
                                    Text(dateFormatter.string(from: item.date))
                                        .font(.system(size: 11))
                                        .foregroundStyle(.white.opacity(0.4))
                                    
                                    Spacer()
                                    
                                    Button {
                                        copyToClipboard(item.text)
                                    } label: {
                                        Image(systemName: "doc.on.doc")
                                            .font(.system(size: 12))
                                            .foregroundStyle(.white.opacity(0.5))
                                    }
                                    .buttonStyle(.plain)
                                    .help("Copier le texte")
                                }
                                
                                Text(item.text)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white.opacity(0.9))
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
