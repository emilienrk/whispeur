# Design : Initial prompt, filtre VAD, version moteur & mises à jour Sparkle

**Date :** 2026-07-09
**Statut :** validé

## Objectif

Quatre ajouts à Whispeur :

1. Réglage **initial prompt** transmis au moteur Whisper.
2. Réglage **filtre VAD** (Silero) intégré à whisper.cpp.
3. Affichage de la **version du moteur** whisper.cpp embarqué.
4. **Mises à jour automatiques de l'app** via Sparkle 2 (le moteur étant lié
   statiquement, sa mise à jour passe par une release de l'app).

## Contexte technique

- whisper.cpp est un submodule (v1.9.1) compilé en lib statique avec Metal
  (`build-whisper.sh`). La version vendorée expose `initial_prompt`,
  `params.vad` / `vad_model_path` / `vad_params`, et `whisper_version()`.
- Les réglages suivent le pattern `AppSettings` (@Observable + UserDefaults)
  → `WhisperEngineConfig` (Sendable) → `WhisperService` (actor).
- `ModelManager` télécharge les modèles ggml dans
  `Application Support/Whispeur/Models/` via `WhisperModelDescriptor`.
- Repo GitHub `emilienrk/whispeur` désormais **public** ; releases via
  `make dmg` existant. App signée **ad-hoc** (pas de Developer ID).

## 1. Initial prompt

- `AppSettings.initialPrompt: String` (clé UserDefaults `initialPrompt`,
  défaut `""`).
- `WhisperEngineConfig.initialPrompt: String` ; dans
  `WhisperService.transcribe`, si non vide, passé à `params.initial_prompt`.
- Lifetimes C : `transcribe` gère déjà `language.whisperCode` via
  `withCString` ; introduire un helper pour maintenir vivantes les chaînes C
  (langue, prompt, chemin VAD) pendant l'appel `whisper_full` sans imbrication
  de closures.
- UI : nouvelle carte « Prompt initial » dans `EngineSection` avec champ texte
  multiligne + description (vocabulaire spécifique, noms propres, style de
  ponctuation). Champ vide = fonctionnalité inactive.

## 2. Filtre VAD (Silero)

- `AppSettings.vadEnabled: Bool` (clé `vadEnabled`, défaut `false`).
- Paramètres VAD aux défauts whisper.cpp (`whisper_vad_default_params()`),
  pas de réglages fins exposés (YAGNI).
- Modèle requis : `ggml-silero-v5.1.2.bin` (~1 Mo) depuis
  `https://huggingface.co/ggml-org/whisper-vad/resolve/main/ggml-silero-v5.1.2.bin`.
- Réutilisation de `ModelManager` avec un `WhisperModelDescriptor` dédié hors
  catalogue (constante statique, ex. `WhisperModelDescriptor.vadSilero`),
  stocké dans le même dossier Models.
- UX : activer le toggle déclenche le téléchargement si absent (progression
  affichée, toggle inerte pendant le téléchargement). Le désactiver conserve
  le fichier en cache.
- `WhisperService.transcribe` : si `config.vadEnabled` **et** fichier présent
  → `params.vad = true`, `params.vad_model_path = <chemin>`,
  `params.vad_params = whisper_vad_default_params()`. Sinon transcription
  normale (dégradation silencieuse + log).
- `WhisperEngineConfig` : `vadEnabled: Bool` + `vadModelPath: String?`
  (résolu côté MainActor, le service ne touche pas au FileManager pour ça).

## 3. Version du moteur

- Carte « Moteur whisper.cpp » en bas de `EngineSection` affichant :
  - version runtime via `whisper_version()` (ex. `1.9.1`) ;
  - commit court du submodule, embarqué au build.
- Embarquement du commit : script phase (déclarée dans `project.yml`) qui
  exécute `git -C whisper.cpp rev-parse --short HEAD` et génère
  `Whispeur/Generated/EngineBuildInfo.generated.swift` (gitignoré). Fallback
  `"unknown"` si git indisponible.
- Pas de mécanisme de mise à jour du moteur seul : statiquement lié, il est
  mis à jour par une release de l'app (Sparkle).

## 4. Mises à jour de l'app (Sparkle 2)

- Dépendance SPM `sparkle-project/Sparkle` (2.x) déclarée dans `project.yml`.
- `SPUStandardUpdaterController` instancié au lancement
  (`WhispeurApp`/AppDelegate), vérification automatique périodique activée.
- Points d'entrée UI :
  - item « Vérifier les mises à jour… » dans le menu de la barre de statut ;
  - bouton + affichage de la version app dans les réglages (carte
    « À propos / Mises à jour » dans `GeneralSection`).
- Info.plist (via `project.yml`) :
  - `SUFeedURL` = `https://github.com/emilienrk/whispeur/releases/latest/download/appcast.xml`
    (l'appcast est attaché comme asset de **chaque** release ; l'URL `latest`
    reste stable) ;
  - `SUPublicEDKey` = clé publique EdDSA.
- Clés EdDSA générées une fois avec `generate_keys` (Sparkle) ; clé privée en
  Keychain locale, jamais commitée.
- Versionnage : `MARKETING_VERSION` et `CURRENT_PROJECT_VERSION` gérés dans
  `project.yml` ; Sparkle compare `CFBundleVersion`.
- Caveat assumé : app signée ad-hoc. Les updates Sparkle sont validées par
  EdDSA et s'installent sans friction ; seul le premier téléchargement manuel
  du DMG affiche l'avertissement Gatekeeper.

## 5. Pipeline de release

- Nouveau target `make release VERSION=x.y.z` qui :
  1. bump `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` dans `project.yml`
     et régénère le projet (xcodegen) ;
  2. build Release + création du DMG (réutilise `make dmg`) ;
  3. signe le DMG avec `sign_update` (outil Sparkle) ;
  4. régénère `appcast.xml` ;
  5. crée la GitHub Release (tag `vx.y.z`) et uploade DMG + appcast via
     `gh` CLI (prérequis : `brew install gh` + `gh auth login`).
- Échec de n'importe quelle étape = arrêt du script (set -e), rien de publié
  à moitié.

## Tests

- `AppSettingsTests` (nouveaux cas) : persistance et valeurs par défaut de
  `initialPrompt` et `vadEnabled`.
- Test du mapping `AppSettings` → `WhisperEngineConfig` (prompt et VAD
  transmis correctement, `vadModelPath` nil si fichier absent).
- Pas de test réseau pour Sparkle ni le téléchargement VAD (couverts
  manuellement) ; vérification manuelle du cycle update complet avec une
  release de test.

## Hors périmètre

- Réglages fins du VAD (seuil, durées min).
- Notarisation / Developer ID.
- Mise à jour du moteur indépendamment de l'app.
- CI GitHub Actions pour les releases.
