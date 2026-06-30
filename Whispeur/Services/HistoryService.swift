// HistoryService.swift
// Whispeur
//
// Manages the persistent history of transcriptions.

import Foundation
import Observation

@MainActor
@Observable
final class HistoryService {
    var items: [HistoryItem] = []
    
    private let maxItems = 100
    private let fileName = "history.json"
    private var fileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("Whispeur", isDirectory: true)
        return appDir.appendingPathComponent(fileName)
    }
    
    init() {
        loadHistory()
    }
    
    func add(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let newItem = HistoryItem(text: text)
        items.insert(newItem, at: 0)
        
        if items.count > maxItems {
            items = Array(items.prefix(maxItems))
        }
        
        saveHistory()
    }
    
    func clearAll() {
        items.removeAll()
        saveHistory()
    }
    
    private func loadHistory() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            items = try decoder.decode([HistoryItem].self, from: data)
        } catch {
            print("[HistoryService] Failed to load history: \(error)")
        }
    }
    
    private func saveHistory() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(items)
            
            // Ensure directory exists
            let dir = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("[HistoryService] Failed to save history: \(error)")
        }
    }
}
