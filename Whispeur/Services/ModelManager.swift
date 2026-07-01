// ModelManager.swift
// Whispeur
//
// Downloads ggml model files from HuggingFace using URLSessionDownloadTask.
// Reports progress via @Observable state. Supports cancel and delete.

import Foundation
import os

// MARK: - Download state per model

enum ModelDownloadState: Equatable {
    case idle
    case downloading(progress: Double)  // 0.0 ... 1.0
    case installing                     // moving temp file to final location
    case done
    case failed(String)
}

// MARK: - ModelManager

@MainActor
@Observable
final class ModelManager: NSObject {

    // MARK: - Singleton

    static let shared = ModelManager()

    // MARK: - State

    /// Download state keyed by model filename.
    private(set) var downloadStates: [String: ModelDownloadState] = [:]

    // MARK: - Private

    private var activeTasks: [String: URLSessionDownloadTask] = [:]
    private var _session: URLSession?
    private var session: URLSession {
        if let s = _session { return s }
        let config = URLSessionConfiguration.default
        config.allowsCellularAccess = true
        let s = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        _session = s
        return s
    }

    private let logger = Logger(subsystem: "com.whispeur", category: "ModelManager")

    // MARK: - Models directory

    /// Models directory in Application Support. nonisolated(unsafe) so delegates can read it.
    nonisolated(unsafe) static var modelsDirectory: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("Whispeur/Models", isDirectory: true)
    }()

    // MARK: - Public API

    func state(for model: WhisperModelDescriptor) -> ModelDownloadState {
        if model.isDownloaded { return .done }
        return downloadStates[model.filename] ?? .idle
    }

    /// Starts downloading a model. No-op if already downloaded or in progress.
    func download(_ model: WhisperModelDescriptor) {
        guard !model.isDownloaded,
              activeTasks[model.filename] == nil else { return }

        // Ensure the destination directory exists.
        try? FileManager.default.createDirectory(
            at: Self.modelsDirectory,
            withIntermediateDirectories: true
        )

        downloadStates[model.filename] = .downloading(progress: 0)

        let request = URLRequest(url: model.downloadURL)
        let task = session.downloadTask(with: request)
        task.taskDescription = model.filename   // Used in delegate callbacks to identify the model.
        task.resume()
        activeTasks[model.filename] = task

        logger.info("Download started: \(model.filename)")
    }

    /// Cancels an ongoing download.
    func cancel(_ model: WhisperModelDescriptor) {
        activeTasks[model.filename]?.cancel()
        activeTasks.removeValue(forKey: model.filename)
        downloadStates[model.filename] = .idle
        logger.info("Download cancelled: \(model.filename)")
    }

    /// Deletes a downloaded model file.
    func delete(_ model: WhisperModelDescriptor) {
        guard model.isDownloaded else { return }
        try? FileManager.default.removeItem(at: model.localURL)
        downloadStates[model.filename] = .idle
        logger.info("Model deleted: \(model.filename)")
    }
}

// MARK: - URLSessionDownloadDelegate

extension ModelManager: URLSessionDownloadDelegate {

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let filename = downloadTask.taskDescription,
              totalBytesExpectedToWrite > 0 else { return }

        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)

        Task { @MainActor [weak self] in
            self?.downloadStates[filename] = .downloading(progress: progress)
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let filename = downloadTask.taskDescription else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.downloadStates[filename] = .installing
            self.activeTasks.removeValue(forKey: filename)
        }

        // Move temp file → final location on a background thread.
        let destination = Self.modelsDirectory.appendingPathComponent(filename)
        do {
            // Remove stale file if present.
            if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)

            Task { @MainActor [weak self] in
                self?.downloadStates[filename] = .done
                self?.logger.info("Model installed: \(filename)")
            }
        } catch {
            Task { @MainActor [weak self] in
                self?.downloadStates[filename] = .failed(error.localizedDescription)
                self?.logger.error("Install failed for \(filename): \(error)")
            }
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: (any Error)?
    ) {
        guard let error,
              let filename = task.taskDescription,
              (error as NSError).code != NSURLErrorCancelled else { return }

        let message = error.localizedDescription
        Task { @MainActor [weak self] in
            self?.downloadStates[filename] = .failed(message)
            self?.activeTasks.removeValue(forKey: filename)
            self?.logger.error("Download failed for \(filename): \(message)")
        }
    }
}
