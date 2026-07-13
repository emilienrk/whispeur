// UpdaterService.swift
// Whispeur
//
// Wrapper autour de Sparkle : démarre l'updater au lancement et expose
// la vérification manuelle pour le menu et les réglages.

import Foundation
import Sparkle

@MainActor
final class UpdaterService {

    static let shared = UpdaterService()

    private let controller: SPUStandardUpdaterController

    private init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    /// Force l'instanciation (démarre les checks automatiques planifiés).
    func start() {}

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
