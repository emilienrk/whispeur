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
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Historique des transcriptions")
                    .font(.headline)
                
                Spacer()
                
                Button(role: .destructive) {
                    historyService.clearAll()
                } label: {
                    Label("Effacer tout", systemImage: "trash")
                }
                .disabled(historyService.items.isEmpty)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // List
            if historyService.items.isEmpty {
                VStack {
                    Spacer()
                    Image(systemName: "clock")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                        .padding(.bottom, 8)
                    Text("Aucune transcription récente.")
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .controlBackgroundColor))
            } else {
                List(historyService.items) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top) {
                            Text(dateFormatter.string(from: item.date))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            Button {
                                copyToClipboard(item.text)
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.accentColor)
                            .help("Copier le texte")
                        }
                        
                        Text(item.text)
                            .font(.body)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.inset)
                .background(Color(nsColor: .controlBackgroundColor))
            }
        }
        .frame(minWidth: 400, minHeight: 400)
    }
    
    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
