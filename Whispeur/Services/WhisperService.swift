// WhisperService.swift
// Whispeur
//
// Actor Swift servant de pont entre l'application et la bibliothèque C whisper.cpp.
// Garantit la thread-safety exigée par l'API C (un seul accès concurrent par contexte).
//
// Dépendances :
//   - libwhisper.a  (linkée via OTHER_LDFLAGS dans project.yml)
//   - WhisperBridge.h (bridging header qui importe whisper.h)
//   - WhisperModel.swift (WhisperLanguage, WhisperModelDescriptor)

import Foundation

// MARK: - Erreurs

enum WhisperServiceError: Error, LocalizedError {
    case modelNotFound(path: String)
    case contextInitFailed(path: String)
    case transcriptionFailed
    case noModelLoaded

    var errorDescription: String? {
        switch self {
        case .modelNotFound(let path):
            return "Modèle introuvable : \(path)"
        case .contextInitFailed(let path):
            return "Impossible d'initialiser le contexte Whisper pour : \(path)"
        case .transcriptionFailed:
            return "La transcription a échoué (whisper_full a retourné une erreur)."
        case .noModelLoaded:
            return "Aucun modèle Whisper n'est chargé. Appelez loadModel() d'abord."
        }
    }
}

// MARK: - WhisperService (actor)

/// Actor principal de Whispeur.
///
/// Il encapsule le pointeur opaque C `whisper_context` et expose une API Swift async/await
/// propre, thread-safe par conception (grâce au mot-clé `actor`).
///
/// Cycle de vie typique :
/// ```swift
/// let service = WhisperService()
/// try await service.loadModel(at: modelURL, language: .auto)
/// let text = try await service.transcribe(samples: audioBuffer)
/// ```
actor WhisperService {

    // MARK: - État interne

    /// Pointeur opaque C vers le contexte Whisper.
    /// `nonisolated(unsafe)` : requis par Swift 6 pour permettre l'accès depuis `deinit`
    /// (nonisolated par définition). C'est safe car `deinit` garantit l'exclusivité d'accès.
    nonisolated(unsafe) private var context: OpaquePointer?

    /// Langue configurée pour la prochaine transcription.
    private var language: WhisperLanguage = .auto

    /// Chemin du modèle actuellement chargé (pour éviter les rechargements inutiles).
    private var loadedModelPath: String?

    // MARK: - Initialisation / Libération

    init() {}

    deinit {
        // En Swift 6, deinit d'un actor est nonisolated.
        // On libère le contexte C directement ici — le deinit garantit l'exclusivité.
        if let ctx = context {
            whisper_free(ctx)
        }
    }

    /// Libère le contexte C et remet les pointeurs à nil (version actor-isolated).
    private func _freeContext() {
        if let ctx = context {
            whisper_free(ctx)
            context = nil
            loadedModelPath = nil
        }
    }

    // MARK: - Chargement du modèle

    /// Charge un modèle ggml depuis l'URL donnée, avec activation GPU (Metal).
    ///
    /// Si un modèle différent est déjà chargé, l'ancien est libéré avant de charger le nouveau.
    /// Si le même modèle est déjà chargé, cette méthode ne fait rien (pas de rechargement inutile).
    ///
    /// - Parameters:
    ///   - url: Chemin local vers le fichier `.bin` du modèle ggml.
    ///   - language: Langue à utiliser pour la transcription (`.auto` pour la détection automatique).
    /// - Throws: `WhisperServiceError.modelNotFound` si le fichier est absent.
    ///           `WhisperServiceError.contextInitFailed` si l'initialisation du contexte C échoue.
    func loadModel(at url: URL, language: WhisperLanguage = .auto) throws {
        let path = url.path

        // Éviter un rechargement si c'est déjà le bon modèle chargé
        if loadedModelPath == path {
            self.language = language
            return
        }

        guard FileManager.default.fileExists(atPath: path) else {
            throw WhisperServiceError.modelNotFound(path: path)
        }

        // Libérer l'ancien contexte avant d'en créer un nouveau
        _freeContext()

        // Paramètres de contexte : Metal activé sur Apple Silicon
        var ctxParams = whisper_context_default_params()
        ctxParams.use_gpu = true    // Active Metal (GPU) — sans effet si GPU indisponible
        ctxParams.flash_attn = true // Flash Attention : réduit l'empreinte mémoire GPU

        guard let newContext = whisper_init_from_file_with_params(path, ctxParams) else {
            throw WhisperServiceError.contextInitFailed(path: path)
        }

        context = newContext
        loadedModelPath = path
        self.language = language

        print("[WhisperService] Modèle chargé : \(url.lastPathComponent) (GPU=\(ctxParams.use_gpu), FlashAttn=\(ctxParams.flash_attn))")
    }

    /// Décharge le modèle et libère la mémoire associée.
    func unloadModel() {
        _freeContext()
        print("[WhisperService] Contexte libéré.")
    }

    /// Met à jour la langue sans recharger le modèle.
    func setLanguage(_ language: WhisperLanguage) {
        self.language = language
    }

    /// `true` si un modèle est actuellement chargé en mémoire.
    var isModelLoaded: Bool {
        context != nil
    }

    // MARK: - Transcription

    /// Transcrit un buffer audio PCM 16 kHz mono en texte.
    ///
    /// Cette méthode est **synchrone** au sein de l'actor (elle bloque le thread de l'actor
    /// pendant la transcription, garantissant l'exclusivité d'accès au contexte C).
    /// Pour ne pas bloquer l'UI, appelez-la depuis une `Task` ou via `async let`.
    ///
    /// - Parameter samples: Tableau de `Float` PCM linéaire, 16000 Hz, mono.
    ///                      Obtenu depuis `AVAudioEngine` (voir `AudioCaptureService`).
    /// - Returns: Le texte transcrit (concaténation de tous les segments Whisper).
    /// - Throws: `WhisperServiceError.noModelLoaded` si aucun modèle n'est chargé.
    ///           `WhisperServiceError.transcriptionFailed` si `whisper_full` retourne une erreur.
    func transcribe(samples: [Float]) throws -> String {
        guard let ctx = context else {
            throw WhisperServiceError.noModelLoaded
        }

        // Sélection du nombre de threads : laisser 2 cœurs libres (efficacité macOS),
        // plafonné à 8 pour éviter la dégradation sur les grands modèles.
        let maxThreads = max(1, min(8, ProcessInfo.processInfo.processorCount - 2))

        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)

        // Configuration des paramètres de transcription
        params.print_realtime   = false  // Pas de log temps réel (inutile en production)
        params.print_progress   = false  // Pas de barre de progression C
        params.print_timestamps = false  // On gère l'affichage côté Swift
        params.print_special    = false  // Tokens spéciaux (silence, début, fin…)
        params.translate        = false  // Mode transcription pur (pas de traduction)
        params.n_threads        = Int32(maxThreads)
        params.offset_ms        = 0
        params.no_context       = true   // Pas de contexte inter-segments (meilleur pour la dictée)
        params.single_segment   = false  // Plusieurs segments possibles pour les longues dictées

        // Langue : `nil` = détection automatique par Whisper (language_id sur le spectrogramme)
        if let code = language.whisperCode {
            // On doit maintenir le pointeur C en vie pendant tout l'appel à whisper_full.
            // On utilise withCString pour garantir cela dans un bloc fermé.
            var result: Int32 = 0
            code.withCString { cCode in
                params.language = cCode
                samples.withUnsafeBufferPointer { buf in
                    result = whisper_full(ctx, params, buf.baseAddress, Int32(buf.count))
                }
            }
            if result != 0 {
                throw WhisperServiceError.transcriptionFailed
            }
        } else {
            // Détection automatique : language = nil dans l'API C
            params.language = nil
            var result: Int32 = 0
            samples.withUnsafeBufferPointer { buf in
                result = whisper_full(ctx, params, buf.baseAddress, Int32(buf.count))
            }
            if result != 0 {
                throw WhisperServiceError.transcriptionFailed
            }
        }

        return extractTranscription(from: ctx)
    }

    // MARK: - Extraction du texte

    /// Concatène tous les segments produits par Whisper en une seule chaîne.
    private func extractTranscription(from ctx: OpaquePointer) -> String {
        let segmentCount: Int32 = whisper_full_n_segments(ctx)
        guard segmentCount > 0 else { return "" }

        var result = ""
        result.reserveCapacity(Int(segmentCount) * 40) // estimation : ~40 chars/segment

        for i: Int32 in 0..<segmentCount {
            if let cStr = whisper_full_get_segment_text(ctx, i) {
                result += String(cString: cStr)
            }
        }

        // Whisper ajoute souvent un espace initial — on le retire proprement
        return result.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Helpers développement

    /// Retourne l'URL du modèle de test embarqué dans le répertoire `Models/` à côté du projet.
    /// Utile en développement avant que la gestion de téléchargement soit implémentée.
    ///
    /// Cherche d'abord dans `<bundle>/Models/`, puis dans `<project_root>/Models/`.
    static func devModelURL(filename: String = "ggml-base.bin") -> URL? {
        // 1. Dans le bundle de l'app (une fois embarqué)
        if let bundleURL = Bundle.main.url(forResource: filename, withExtension: nil) {
            return bundleURL
        }

        // 2. À côté de l'exécutable (build de développement Xcode)
        let executableURL = Bundle.main.executableURL
        let projectModelsURL = executableURL?
            .deletingLastPathComponent()   // bin/
            .deletingLastPathComponent()   // build/
            .deletingLastPathComponent()   // DerivedData/.../
            // On tente un chemin relatif commun pour le workspace Xcode
        if let base = projectModelsURL {
            // Chemin heuristique Xcode : remonte depuis DerivedData jusqu'au projet
            // Fallback : cherche `Models/ggml-base.bin` dans le dossier courant
            let candidate = base.appendingPathComponent("Models/\(filename)")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        // 3. Chemin absolu connu (répertoire du projet pendant le développement)
        // Ce chemin est fourni en dur uniquement pour les tests initiaux.
        let hardcodedDev = URL(fileURLWithPath: "/Users/emilien/dev/perso/whispeur/Models/\(filename)")
        if FileManager.default.fileExists(atPath: hardcodedDev.path) {
            return hardcodedDev
        }

        return nil
    }
}
