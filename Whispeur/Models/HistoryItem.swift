// HistoryItem.swift
// Whispeur
//
// Represents a single transcription in the history.

import Foundation

struct HistoryItem: Identifiable, Codable, Equatable {
    var id: UUID
    var date: Date
    var text: String

    init(id: UUID = UUID(), date: Date = Date(), text: String) {
        self.id = id
        self.date = date
        self.text = text
    }
}
