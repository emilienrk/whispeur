# Plan d'implémentation — Whispeur

## Contraintes techniques notées

> [!IMPORTANT]
> **Deployment target : macOS 14.0 minimum.**
> Décision prise le 30/06/2026. Justification : permet d'utiliser `@Observable` (Swift 5.9+),
> `SwiftData` si besoin, et les API concurrency modernes sans workarounds.
> Ne jamais rétrograder à macOS 13 sans raison explicite.

> [!TIP]
> **Gestion de la RAM (Lazy Loading & Cache TTL)**
> L'application doit être extrêmement légère. Le modèle Whisper (`.bin`) ne doit **jamais** être chargé en mémoire au lancement de l'application.
> - **Chargement :** Uniquement déclenché au moment où l'utilisateur commence à enregistrer (appui sur le raccourci).
> - **Déchargement immédiat :** Le modèle doit être impérativement purgé de la RAM instantanément (0 seconde) dès que la transcription est terminée.
> Ce compromis sacrifie ~1 seconde de latence sur le premier enregistrement pour économiser plusieurs gigaoctets de RAM en permanence.

---

## État d'avancement

### ✅ Étape 1 — Couche C/Swift (whisper.cpp bridge)
- `WhisperModel.swift` : catalogue des langues et modèles ggml
- `WhisperService.swift` : actor thread-safe, pont vers libwhisper.a
- `project.yml` : headers/libs correctement configurés, `-lc++` ajouté

### ✅ Étape 2 — Moteur audio
- `AudioCaptureService.swift` : AVAudioEngine, downsampling 16 kHz Float32, zéro I/O disque
- `MicrophonePermissionManager.swift` : demande async, lien Préférences Système
- `WhispeurApp.swift` : permission demandée au lancement

### ✅ Étape 3 — Raccourci clavier global (HotKey)
- `HotkeyManager.swift` : `CGEventTap` global sur thread CFRunLoop dédié
- Modes Push-to-Talk et Toggle implémentés
- Swift 6 compliant : `TapSharedState` (nonisolated(unsafe)) pour le partage inter-thread

### ✅ Étape 4 — Colle presse-papier & simulation clavier
- `ClipboardService.swift` : copie NSPasteboard + simulation CGEvent Cmd+V
- Fallback notification `UNUserNotificationCenter` si Accessibility absent
- `RecordingCoordinator.swift` : orchestre le flux complet hotkey → audio → whisper → paste
  - Lazy load du modèle en parallèle de l'audio (latence cachée)
  - Déchargement immédiat 0s après transcription (politique RAM)
- `AppDelegate` mis à jour : connecte tous les services au démarrage

### 🔲 Étape 5 — Interface Settings (SwiftUI)
- Sélection du raccourci
- Sélection de la langue
- Gestion/téléchargement des modèles
- Guide permissions (micro + accessibilité)

### 🔲 Étape 6 — Icône menu bar & feedback visuel
- `NSStatusItem` avec animation pendant l'enregistrement
- Notification macOS si le collage échoue

---

## Choix techniques arrêtés

| Sujet | Choix | Raison |
|---|---|---|
| Deployment target | **macOS 14.0** | `@Observable`, APIs modernes |
| Accélération | **Metal (GPU)** | `params.use_gpu = true` dans WhisperService |
| CoreML | ❌ Écarté | Trop lourd pour v1, Metal suffisant |
| Audio | **AVAudioEngine** | Zéro I/O disque, downsampling temps-réel |
| Paste auto | **CGEvent Cmd+V** | Nécessite droit Accessibility |
| UI | **SwiftUI** | Natif, léger, maîtrisé |
| Observabilité | **@Observable** | Disponible macOS 14+, plus moderne que ObservableObject |
