// MicrophonePermissionManager.swift
// Whispeur
//
// Gestion de la permission d'accès au microphone sur macOS.
// Centralise la demande d'autorisation et expose un état observable
// pour que l'UI puisse réagir proprement.

import AVFoundation
import AppKit
import Foundation

// MARK: - État de la permission

enum MicrophonePermissionStatus: Equatable {
    /// Statut non encore déterminé (avant toute demande)
    case undetermined
    /// Permission accordée — l'enregistrement peut démarrer
    case granted
    /// Permission refusée — l'UI doit guider vers les Préférences Système
    case denied
    /// Statut inconnu / non applicable (cas exceptionnel)
    case restricted
}

// MARK: - MicrophonePermissionManager

/// Gestionnaire de permission microphone.
///
/// Doit être instancié et utilisé sur le `@MainActor` (généralement dans l'`AppDelegate`
/// ou dans un `@Observable` ViewModel d'application).
@MainActor
@Observable
final class MicrophonePermissionManager {

    // MARK: - État observable

    /// Statut courant de la permission microphone.
    private(set) var status: MicrophonePermissionStatus = .undetermined

    // MARK: - Initialisation

    init() {
        // Lire le statut actuel sans déclencher de dialog
        status = Self.currentStatus()
    }

    // MARK: - API publique

    /// Demande la permission microphone si elle n'a pas encore été accordée.
    ///
    /// Si la permission est déjà accordée ou refusée, cette méthode met simplement
    /// à jour l'état observable sans afficher de dialog.
    ///
    /// À appeler au lancement de l'app (dans `applicationDidFinishLaunching`).
    func requestIfNeeded() async {
        let current = Self.currentStatus()

        // Si déjà déterminé, on met à jour et on sort
        if current != .undetermined {
            status = current
            return
        }

        // Lance la demande système (affiche le dialog macOS)
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        status = granted ? .granted : .denied
    }

    /// Ouvre les Préférences Système à la page Confidentialité > Microphone.
    /// À utiliser dans le bouton "Ouvrir les préférences" de l'UI d'erreur.
    func openSystemPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    /// `true` si l'app peut enregistrer de l'audio.
    var canRecord: Bool {
        status == .granted
    }

    // MARK: - Helpers statiques

    /// Lit le statut actuel sans déclencher de dialog.
    static func currentStatus() -> MicrophonePermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined: return .undetermined
        case .authorized:    return .granted
        case .denied:        return .denied
        case .restricted:    return .restricted
        @unknown default:    return .restricted
        }
    }
}
