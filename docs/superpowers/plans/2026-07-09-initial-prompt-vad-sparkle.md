# Initial Prompt, VAD, Version Moteur & Sparkle — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ajouter le réglage initial prompt et le filtre VAD Silero au moteur Whisper, afficher la version du moteur embarqué, et mettre en place les mises à jour automatiques de l'app via Sparkle 2 avec un pipeline de release `make release`.

**Architecture:** Les nouveaux réglages suivent le pattern existant `AppSettings` (@Observable + UserDefaults) → `WhisperEngineConfig` (struct Sendable) → `WhisperService` (actor whisper.cpp). Le modèle VAD est téléchargé par le `ModelManager` existant via un `WhisperModelDescriptor` hors catalogue. Sparkle est intégré en SPM avec appcast hébergé sur GitHub Releases.

**Tech Stack:** Swift 6, SwiftUI, whisper.cpp 1.9.1 (submodule, lib statique), Sparkle 2 (SPM), xcodegen, Swift Testing, gh CLI.

## Global Constraints

- Swift 6, macOS deployment target 26.0, framework de test **Swift Testing** (`import Testing`, pas XCTest).
- Le projet Xcode est **généré par xcodegen** : après tout ajout/suppression de fichier source, relancer `xcodegen generate` sinon le fichier n'est pas dans le target.
- Commande de test : `xcodebuild -project Whispeur.xcodeproj -scheme WhispeurTests test -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData` — **doit tourner hors sandbox Claude Code** (xcodebuild échoue en sandbox avec « Operation not permitted »).
- Build app : `xcodebuild -project Whispeur.xcodeproj -scheme Whispeur -configuration Release build SYMROOT="$PWD/build"` (hors sandbox aussi).
- Le target de tests compile directement les sources listées dans `project.yml` (pas de `@testable import`). Il inclut `Whispeur/Models` et certains fichiers de `Whispeur/Services` — **ne pas référencer `ModelManager` ni `UpdaterService` depuis `AppSettings` ou les Models**.
- Tout texte UI en **français**, style existant (tailles/opacités des `SettingsCard` copiées des sections voisines).
- Les tests qui modifient `AppSettings.shared` doivent sauvegarder/restaurer la valeur (UserDefaults réels du runner).
- Repo GitHub public : `emilienrk/whispeur`.

---

### Task 1 : Réglage « initial prompt » (AppSettings → WhisperEngineConfig → WhisperService)

**Files:**
- Create: `WhispeurTests/EngineConfigTests.swift`
- Modify: `Whispeur/Models/AppSettings.swift`
- Modify: `Whispeur/Services/WhisperService.swift`
- Modify: `Whispeur/Services/RecordingCoordinator.swift:171-182`

**Interfaces:**
- Produces: `AppSettings.initialPrompt: String` (défaut `""`), `AppSettings.engineConfig: WhisperEngineConfig` (propriété calculée, utilisée par RecordingCoordinator et les tests), `WhisperEngineConfig.initialPrompt: String`.
- La Task 2 étendra `engineConfig` et `WhisperEngineConfig` avec les champs VAD ; la Task 3 utilisera `$settings.initialPrompt` dans l'UI.

- [ ] **Step 1 : Écrire le test qui échoue**

Créer `WhispeurTests/EngineConfigTests.swift` :

```swift
// EngineConfigTests.swift
// WhispeurTests

import Testing
import Foundation

@MainActor
struct EngineConfigTests {

    @Test("initialPrompt is persisted and flows into the engine config")
    func initialPromptMapping() {
        let s = AppSettings.shared
        let saved = s.initialPrompt
        defer { s.initialPrompt = saved }

        s.initialPrompt = "Whispeur, xcodegen, ggml"

        #expect(s.engineConfig.initialPrompt == "Whispeur, xcodegen, ggml")
        #expect(UserDefaults.standard.string(forKey: "initialPrompt") == "Whispeur, xcodegen, ggml")
    }

    @Test("engine config mirrors the existing engine settings")
    func existingSettingsMapping() {
        let s = AppSettings.shared
        let savedBeam = s.useBeamSearch
        let savedTemp = s.temperature
        defer {
            s.useBeamSearch = savedBeam
            s.temperature = savedTemp
        }

        s.useBeamSearch = true
        s.temperature = 0.3

        let config = s.engineConfig
        #expect(config.useBeamSearch == true)
        #expect(abs(config.temperature - 0.3) < 0.0001)
    }
}
```

- [ ] **Step 2 : Régénérer le projet et vérifier l'échec**

```bash
xcodegen generate
xcodebuild -project Whispeur.xcodeproj -scheme WhispeurTests test -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData
```

Attendu : **échec de compilation** — `value of type 'AppSettings' has no member 'initialPrompt'` (et `engineConfig`).

- [ ] **Step 3 : Implémenter dans AppSettings**

Dans `Whispeur/Models/AppSettings.swift` :

1. Dans `private init()`, après la ligne `_modelUnloadDelay = ...` :

```swift
        _initialPrompt         = ud.string(forKey: "initialPrompt") ?? ""
```

2. À la fin de la section `// MARK: - Engine (Whisper params)` (après la propriété `modelUnloadDelay`) :

```swift
    private var _initialPrompt: String {
        didSet { UserDefaults.standard.set(_initialPrompt, forKey: "initialPrompt") }
    }
    /// Context text fed to the decoder before each dictation (vocabulary, proper nouns, punctuation style). Empty = disabled.
    var initialPrompt: String {
        get { _initialPrompt }
        set { _initialPrompt = newValue }
    }

    /// Engine config snapshot passed to WhisperService for one transcription.
    var engineConfig: WhisperEngineConfig {
        WhisperEngineConfig(
            useBeamSearch: useBeamSearch,
            beamSize: beamSize,
            temperature: Float(temperature),
            noSpeechThreshold: Float(noSpeechThreshold),
            conditionOnPreviousText: conditionOnPreviousText,
            useGPU: useGPU,
            initialPrompt: initialPrompt
        )
    }
```

3. Dans `Whispeur/Services/WhisperService.swift`, ajouter le champ à `WhisperEngineConfig` :

```swift
struct WhisperEngineConfig: Sendable {
    var useBeamSearch: Bool
    var beamSize: Int
    var temperature: Float
    var noSpeechThreshold: Float
    var conditionOnPreviousText: Bool
    var useGPU: Bool
    var initialPrompt: String

    static let `default` = WhisperEngineConfig(
        useBeamSearch: false,
        beamSize: 5,
        temperature: 0.0,
        noSpeechThreshold: 0.6,
        conditionOnPreviousText: false,
        useGPU: true,
        initialPrompt: ""
    )
}
```

- [ ] **Step 4 : Passer le prompt au moteur (remplacement du withCString imbriqué)**

Dans `WhisperService.transcribe`, remplacer tout le bloc entre `params.language = nil  // overridden below if set` (inclus) et `if result != 0` (exclus) par :

```swift
        if config.useBeamSearch {
            params.beam_search.beam_size = Int32(config.beamSize)
        }

        // Les chaînes C doivent survivre à whisper_full : strdup + defer free
        // évite l'imbrication de withCString pour plusieurs chaînes optionnelles.
        let cLanguage: UnsafeMutablePointer<CChar>? = language.whisperCode.flatMap { strdup($0) }
        let cPrompt: UnsafeMutablePointer<CChar>? = config.initialPrompt.isEmpty ? nil : strdup(config.initialPrompt)
        defer {
            free(cLanguage)
            free(cPrompt)
        }
        params.language = UnsafePointer(cLanguage)
        params.initial_prompt = UnsafePointer(cPrompt)

        var result: Int32 = 0
        samples.withUnsafeBufferPointer { buf in
            result = whisper_full(ctx, params, buf.baseAddress, Int32(buf.count))
        }
```

(La ligne `params.language = nil` et l'ancien `if let code = language.whisperCode { ... } else { ... }` disparaissent. Supprimer aussi le `if config.useBeamSearch` original devenu doublon.)

- [ ] **Step 5 : Utiliser engineConfig dans RecordingCoordinator**

Dans `RecordingCoordinator.runTranscriptionAndPaste`, remplacer :

```swift
        let s = AppSettings.shared
        let engineConfig = WhisperEngineConfig(
            useBeamSearch: s.useBeamSearch,
            beamSize: s.beamSize,
            temperature: Float(s.temperature),
            noSpeechThreshold: Float(s.noSpeechThreshold),
            conditionOnPreviousText: s.conditionOnPreviousText,
            useGPU: s.useGPU
        )
```

par :

```swift
        let engineConfig = AppSettings.shared.engineConfig
```

- [ ] **Step 6 : Vérifier que les tests passent**

```bash
xcodebuild -project Whispeur.xcodeproj -scheme WhispeurTests test -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData
```

Attendu : PASS (tous les tests, y compris les 2 nouveaux).

- [ ] **Step 7 : Commit**

```bash
git add WhispeurTests/EngineConfigTests.swift Whispeur/Models/AppSettings.swift Whispeur/Services/WhisperService.swift Whispeur/Services/RecordingCoordinator.swift
git commit -m "feat: add initial prompt setting wired into whisper engine"
```

---

### Task 2 : Filtre VAD Silero (descripteur, réglage, moteur)

**Files:**
- Modify: `Whispeur/Models/WhisperModel.swift` (fin de fichier)
- Modify: `Whispeur/Models/AppSettings.swift`
- Modify: `Whispeur/Services/WhisperService.swift`
- Test: `WhispeurTests/EngineConfigTests.swift`

**Interfaces:**
- Consumes: `AppSettings.engineConfig` et `WhisperEngineConfig` de la Task 1.
- Produces: `WhisperModelDescriptor.vadSilero: WhisperModelDescriptor` (statique, hors catalogue — utilisé par la Task 3 pour le téléchargement), `AppSettings.vadEnabled: Bool` (défaut `false`), `WhisperEngineConfig.vadEnabled: Bool` + `vadModelPath: String?`.

- [ ] **Step 1 : Écrire les tests qui échouent**

Ajouter à `WhispeurTests/EngineConfigTests.swift` (dans la struct `EngineConfigTests`) :

```swift
    @Test("VAD disabled produces nil model path")
    func vadDisabledNilPath() {
        let s = AppSettings.shared
        let saved = s.vadEnabled
        defer { s.vadEnabled = saved }

        s.vadEnabled = false

        #expect(s.engineConfig.vadEnabled == false)
        #expect(s.engineConfig.vadModelPath == nil)
    }

    @Test("VAD enabled resolves the path only when the model file exists")
    func vadEnabledPathResolution() {
        let s = AppSettings.shared
        let saved = s.vadEnabled
        defer { s.vadEnabled = saved }

        s.vadEnabled = true
        let model = WhisperModelDescriptor.vadSilero

        if model.isDownloaded {
            #expect(s.engineConfig.vadModelPath == model.localURL.path(percentEncoded: false))
        } else {
            #expect(s.engineConfig.vadModelPath == nil)
        }
    }
```

- [ ] **Step 2 : Vérifier l'échec**

```bash
xcodebuild -project Whispeur.xcodeproj -scheme WhispeurTests test -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData
```

Attendu : **échec de compilation** — `type 'WhisperModelDescriptor' has no member 'vadSilero'`, `'AppSettings' has no member 'vadEnabled'`.

- [ ] **Step 3 : Implémenter le descripteur VAD**

Dans `Whispeur/Models/WhisperModel.swift`, dans la struct `WhisperModelDescriptor`, après `static var testModel` :

```swift
    /// Modèle Silero VAD requis par le filtre VAD de whisper.cpp.
    /// Hors catalogue : téléchargé automatiquement quand le VAD est activé.
    static let vadSilero = WhisperModelDescriptor(
        name: "silero-vad-v5.1.2",
        sizeInfo: "~1 MiB",
        downloadURL: URL(string: "https://huggingface.co/ggml-org/whisper-vad/resolve/main/ggml-silero-v5.1.2.bin")!,
        filename: "ggml-silero-v5.1.2.bin",
        isEnglishOnly: false
    )
```

(L'init membre à membre est synthétisé : le seul init custom est dans une extension, il ne le supprime pas.)

- [ ] **Step 4 : Implémenter le réglage et étendre engineConfig**

Dans `Whispeur/Models/AppSettings.swift` :

1. Dans `private init()`, après `_initialPrompt = ...` :

```swift
        _vadEnabled            = (ud.object(forKey: "vadEnabled") as? Bool) ?? false
```

2. Après la propriété `initialPrompt` :

```swift
    private var _vadEnabled: Bool {
        didSet { UserDefaults.standard.set(_vadEnabled, forKey: "vadEnabled") }
    }
    /// Silero VAD filter: skips non-speech audio before transcription (needs the VAD model file).
    var vadEnabled: Bool {
        get { _vadEnabled }
        set { _vadEnabled = newValue }
    }
```

3. Remplacer la propriété `engineConfig` par :

```swift
    /// Engine config snapshot passed to WhisperService for one transcription.
    /// Resolves the VAD model path here (MainActor) so the actor never touches FileManager for it.
    var engineConfig: WhisperEngineConfig {
        let vadModel = WhisperModelDescriptor.vadSilero
        return WhisperEngineConfig(
            useBeamSearch: useBeamSearch,
            beamSize: beamSize,
            temperature: Float(temperature),
            noSpeechThreshold: Float(noSpeechThreshold),
            conditionOnPreviousText: conditionOnPreviousText,
            useGPU: useGPU,
            initialPrompt: initialPrompt,
            vadEnabled: vadEnabled,
            vadModelPath: (vadEnabled && vadModel.isDownloaded) ? vadModel.localURL.path(percentEncoded: false) : nil
        )
    }
```

4. Dans `WhisperService.swift`, étendre `WhisperEngineConfig` :

```swift
struct WhisperEngineConfig: Sendable {
    var useBeamSearch: Bool
    var beamSize: Int
    var temperature: Float
    var noSpeechThreshold: Float
    var conditionOnPreviousText: Bool
    var useGPU: Bool
    var initialPrompt: String
    var vadEnabled: Bool
    var vadModelPath: String?

    static let `default` = WhisperEngineConfig(
        useBeamSearch: false,
        beamSize: 5,
        temperature: 0.0,
        noSpeechThreshold: 0.6,
        conditionOnPreviousText: false,
        useGPU: true,
        initialPrompt: "",
        vadEnabled: false,
        vadModelPath: nil
    )
}
```

- [ ] **Step 5 : Brancher le VAD dans transcribe**

Dans `WhisperService.transcribe`, remplacer tout le bloc écrit à la Task 1 (du commentaire `// Les chaînes C...` jusqu'à la fermeture de `samples.withUnsafeBufferPointer { ... }` incluse) par le bloc final suivant (ajout de `cVadPath` et du branchement VAD ; les lignes `var result` / `whisper_full` sont inchangées mais répétées ici pour lever toute ambiguïté) :

```swift
        // Les chaînes C doivent survivre à whisper_full : strdup + defer free
        // évite l'imbrication de withCString pour plusieurs chaînes optionnelles.
        let cLanguage: UnsafeMutablePointer<CChar>? = language.whisperCode.flatMap { strdup($0) }
        let cPrompt: UnsafeMutablePointer<CChar>? = config.initialPrompt.isEmpty ? nil : strdup(config.initialPrompt)
        let cVadPath: UnsafeMutablePointer<CChar>? = config.vadModelPath.flatMap { strdup($0) }
        defer {
            free(cLanguage)
            free(cPrompt)
            free(cVadPath)
        }
        params.language = UnsafePointer(cLanguage)
        params.initial_prompt = UnsafePointer(cPrompt)

        if config.vadEnabled, let cVadPath {
            // vadModelPath est résolu côté MainActor : non-nil ⟹ le fichier existe.
            params.vad = true
            params.vad_model_path = UnsafePointer(cVadPath)
            params.vad_params = whisper_vad_default_params()
        }

        var result: Int32 = 0
        samples.withUnsafeBufferPointer { buf in
            result = whisper_full(ctx, params, buf.baseAddress, Int32(buf.count))
        }
```

- [ ] **Step 6 : Vérifier que les tests passent**

```bash
xcodebuild -project Whispeur.xcodeproj -scheme WhispeurTests test -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData
```

Attendu : PASS.

- [ ] **Step 7 : Commit**

```bash
git add WhispeurTests/EngineConfigTests.swift Whispeur/Models/WhisperModel.swift Whispeur/Models/AppSettings.swift Whispeur/Services/WhisperService.swift
git commit -m "feat: add Silero VAD filter option wired into whisper engine"
```

---

### Task 3 : UI onglet Moteur — prompt initial et toggle VAD avec téléchargement

**Files:**
- Modify: `Whispeur/Views/EngineSection.swift`

**Interfaces:**
- Consumes: `$settings.initialPrompt`, `$settings.vadEnabled` (Tasks 1-2), `WhisperModelDescriptor.vadSilero` (Task 2), `ModelManager.shared` + `ModelDownloadState` (existants), `SettingsCard`/`SectionHeader`/`SettingsToggleRow` (existants).
- Produces: rien de consommé par les autres tasks.

- [ ] **Step 1 : Ajouter la carte « Prompt initial »**

Dans `EngineSection.body`, insérer après la carte `// MARK: - Quality sliders` (avant `// MARK: - Context & hardware`) :

```swift
            // MARK: - Initial prompt
            SettingsCard {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(icon: "text.quote", title: "Prompt initial")

                    TextEditor(text: $settings.initialPrompt)
                        .font(.system(size: 13))
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .frame(height: 70)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                                )
                        )

                    Text("Donné au modèle comme contexte avant chaque dictée : vocabulaire spécifique, noms propres, style de ponctuation. Vide = désactivé.")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.3))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
```

- [ ] **Step 2 : Ajouter la carte VAD**

Toujours dans `EngineSection.body`, insérer juste après la carte « Prompt initial » :

```swift
            // MARK: - VAD
            SettingsCard {
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(icon: "waveform.badge.mic", title: "Détection de voix (VAD)")
                    VADToggleRow(settings: settings)
                }
            }
```

Et en fin de fichier (après `EngineSliderRow`), ajouter la vue :

```swift
// MARK: - VAD toggle row (avec téléchargement du modèle Silero)

private struct VADToggleRow: View {
    @Bindable var settings: AppSettings

    var body: some View {
        let model = WhisperModelDescriptor.vadSilero
        let state = ModelManager.shared.state(for: model)

        VStack(alignment: .leading, spacing: 8) {
            SettingsToggleRow(
                icon: "waveform.and.mic",
                label: "Filtre VAD (Silero)",
                description: "Ignore les passages sans parole avant la transcription. Réduit les hallucinations sur les silences.",
                isOn: Binding(
                    get: { settings.vadEnabled },
                    set: { enabled in
                        settings.vadEnabled = enabled
                        if enabled && !model.isDownloaded {
                            ModelManager.shared.download(model)
                        }
                    }
                )
            )

            if settings.vadEnabled {
                switch state {
                case .downloading(let progress):
                    HStack(spacing: 8) {
                        ProgressView(value: progress)
                            .frame(maxWidth: 160)
                        Text("Téléchargement du modèle VAD… \(Int(progress * 100)) %")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                case .installing:
                    Text("Installation…")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                case .failed(let message):
                    Text("Échec du téléchargement : \(message)")
                        .font(.system(size: 11))
                        .foregroundStyle(.red.opacity(0.8))
                case .idle:
                    Text("Modèle VAD manquant — désactivez puis réactivez pour relancer le téléchargement.")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange.opacity(0.8))
                case .done:
                    EmptyView()
                }
            }
        }
    }
}
```

- [ ] **Step 3 : Builder et vérifier**

```bash
xcodebuild -project Whispeur.xcodeproj -scheme Whispeur -configuration Release build SYMROOT="$PWD/build"
```

Attendu : BUILD SUCCEEDED.

Vérification manuelle (si session interactive) : lancer l'app, ouvrir Paramètres → Moteur, taper un prompt, activer le VAD → la progression s'affiche puis disparaît, le fichier `~/Library/Application Support/Whispeur/Models/ggml-silero-v5.1.2.bin` existe.

- [ ] **Step 4 : Commit**

```bash
git add Whispeur/Views/EngineSection.swift
git commit -m "feat(ui): add initial prompt field and VAD toggle with model download"
```

---

### Task 4 : Version du moteur (fichier généré + carte UI)

**Files:**
- Create: `scripts/generate-engine-info.sh` (exécutable)
- Modify: `project.yml` (preBuildScripts + ENABLE_USER_SCRIPT_SANDBOXING)
- Modify: `Makefile` (target setup)
- Modify: `.gitignore`
- Modify: `Whispeur/Views/EngineSection.swift`

**Interfaces:**
- Produces: `EngineBuildInfo.whisperCommit: String` (enum généré, target app uniquement). `whisper_version()` vient du bridging header existant.

- [ ] **Step 1 : Créer le script de génération**

`scripts/generate-engine-info.sh` :

```bash
#!/usr/bin/env bash
# Génère Whispeur/Generated/EngineBuildInfo.generated.swift avec le commit
# du submodule whisper.cpp. Idempotent : ne réécrit pas si inchangé.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT/Whispeur/Generated"
OUT="$OUT_DIR/EngineBuildInfo.generated.swift"

COMMIT="$(git -C "$ROOT/whisper.cpp" rev-parse --short HEAD 2>/dev/null || echo unknown)"

if [ -f "$OUT" ] && grep -q "\"$COMMIT\"" "$OUT"; then
    exit 0
fi

mkdir -p "$OUT_DIR"
cat > "$OUT" <<EOF
// EngineBuildInfo.generated.swift
// Généré par scripts/generate-engine-info.sh — ne pas éditer, ne pas committer.

enum EngineBuildInfo {
    static let whisperCommit = "$COMMIT"
}
EOF
echo "EngineBuildInfo: whisper.cpp @ $COMMIT"
```

Puis :

```bash
chmod +x scripts/generate-engine-info.sh
./scripts/generate-engine-info.sh
```

Attendu : affiche `EngineBuildInfo: whisper.cpp @ f049fff` et crée le fichier.

- [ ] **Step 2 : Brancher xcodegen, Makefile et gitignore**

1. `project.yml`, target `Whispeur` — ajouter après `sources:` (même niveau que `settings:`) :

```yaml
    preBuildScripts:
      - name: Generate EngineBuildInfo
        script: |
          "$SRCROOT/scripts/generate-engine-info.sh"
        basedOnDependencyAnalysis: false
```

2. `project.yml`, target `Whispeur`, dans `settings.base` — ajouter :

```yaml
        ENABLE_USER_SCRIPT_SANDBOXING: "NO"
```

3. `Makefile` — remplacer le target `setup` par :

```make
setup:
	./build-whisper.sh
	./scripts/generate-engine-info.sh
	xcodegen generate
```

(Le script doit tourner **avant** xcodegen pour que le fichier généré existe et soit inclus dans le projet.)

4. `.gitignore` — ajouter la ligne :

```
Whispeur/Generated/
```

- [ ] **Step 3 : Ajouter la carte « Moteur whisper.cpp »**

Dans `EngineSection.body`, tout en bas (après la carte `// MARK: - Context & hardware`) :

```swift
            // MARK: - Engine info
            SettingsCard {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(icon: "info.circle.fill", title: "Moteur whisper.cpp")

                    HStack {
                        Text("Version")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.7))
                        Spacer()
                        Text(verbatim: String(cString: whisper_version()))
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.9))
                    }

                    HStack {
                        Text("Commit")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.7))
                        Spacer()
                        Text(verbatim: EngineBuildInfo.whisperCommit)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.9))
                    }

                    Text("Le moteur est intégré à l'app : il se met à jour avec les mises à jour de Whispeur.")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
```

- [ ] **Step 4 : Régénérer, builder, vérifier**

```bash
xcodegen generate
xcodebuild -project Whispeur.xcodeproj -scheme Whispeur -configuration Release build SYMROOT="$PWD/build"
xcodebuild -project Whispeur.xcodeproj -scheme WhispeurTests test -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData
```

Attendu : BUILD SUCCEEDED + tests PASS (le target de tests n'inclut pas Views ni Generated, il ne doit pas casser).

- [ ] **Step 5 : Commit**

```bash
git add scripts/generate-engine-info.sh project.yml Makefile .gitignore Whispeur/Views/EngineSection.swift
git commit -m "feat: show embedded whisper.cpp version and commit in engine settings"
```

---

### Task 5 : Intégration Sparkle 2 (SPM, service, UI, clés EdDSA)

**Files:**
- Modify: `project.yml` (packages, dependency, Info.plist, versions)
- Create: `Whispeur/Services/UpdaterService.swift`
- Modify: `Whispeur/App/WhispeurApp.swift` (AppDelegate)
- Modify: `Whispeur/Views/StatusBarController.swift`
- Modify: `Whispeur/Views/GeneralSection.swift`
- Modify: `Makefile` + `.gitignore` (outils Sparkle)

**Interfaces:**
- Produces: `UpdaterService.shared.checkForUpdates()` (@MainActor), utilisé par le menu et les réglages. `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` dans project.yml, consommés par la Task 6.

- [ ] **Step 1 : Déclarer Sparkle et les versions dans project.yml**

1. Au niveau racine de `project.yml` (après le bloc `options:`) :

```yaml
packages:
  Sparkle:
    url: https://github.com/sparkle-project/Sparkle
    from: "2.6.0"
```

2. Target `Whispeur` : remplacer `dependencies: []` par :

```yaml
    dependencies:
      - package: Sparkle
```

3. Target `Whispeur`, `info.properties` — ajouter :

```yaml
        CFBundleShortVersionString: "$(MARKETING_VERSION)"
        CFBundleVersion: "$(CURRENT_PROJECT_VERSION)"
        SUFeedURL: "https://github.com/emilienrk/whispeur/releases/latest/download/appcast.xml"
        SUPublicEDKey: "SPARKLE_PUBLIC_KEY_PLACEHOLDER"
        SUEnableAutomaticChecks: true
```

4. Target `Whispeur`, `settings.base` — ajouter :

```yaml
        MARKETING_VERSION: "1.0.0"
        CURRENT_PROJECT_VERSION: "1"
```

(Ne PAS ajouter Sparkle au target `WhispeurTests` — il ne compile pas `UpdaterService`.)

- [ ] **Step 2 : Télécharger les outils Sparkle et générer les clés EdDSA**

1. `Makefile` — ajouter (et compléter `.PHONY`) :

```make
SPARKLE_VERSION = 2.6.4

sparkle-tools: tools/sparkle/bin/generate_keys

tools/sparkle/bin/generate_keys:
	mkdir -p tools/sparkle
	curl -L -o /tmp/sparkle.tar.xz https://github.com/sparkle-project/Sparkle/releases/download/$(SPARKLE_VERSION)/Sparkle-$(SPARKLE_VERSION).tar.xz
	tar -xJf /tmp/sparkle.tar.xz -C tools/sparkle
```

2. `.gitignore` — ajouter :

```
tools/
releases/
```

3. Générer les clés (écrit la clé privée dans le Keychain de session, affiche la publique) :

```bash
make sparkle-tools
./tools/sparkle/bin/generate_keys
```

Attendu : sortie contenant `Public key: <base64>`. **Si la commande échoue en sandbox (accès Keychain), la relancer hors sandbox ou demander à l'utilisateur de taper `! ./tools/sparkle/bin/generate_keys`.**

4. Remplacer `SPARKLE_PUBLIC_KEY_PLACEHOLDER` dans `project.yml` par la clé publique affichée.

- [ ] **Step 3 : Créer UpdaterService**

`Whispeur/Services/UpdaterService.swift` :

```swift
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
```

- [ ] **Step 4 : Brancher AppDelegate, menu et réglages**

1. `WhispeurApp.swift`, dans `AppDelegate.applicationDidFinishLaunching`, après `sc.hotkeyManager.startListening()` :

```swift
        // Démarre Sparkle (checks automatiques + manuels).
        UpdaterService.shared.start()
```

2. `StatusBarController.buildMenu()`, juste avant la création de `settingsItem` :

```swift
        let updateItem = NSMenuItem(title: String(localized: "Vérifier les mises à jour…"), action: #selector(checkForUpdates), keyEquivalent: "")
        updateItem.target = self
        updateItem.image = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: nil)
        menu.addItem(updateItem)
```

Et dans la section `// MARK: - Actions` :

```swift
    @objc private func checkForUpdates() {
        UpdaterService.shared.checkForUpdates()
    }
```

3. `GeneralSection.body`, après la carte `// MARK: - System` :

```swift
            // MARK: - Updates
            SettingsCard {
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(icon: "arrow.down.circle.fill", title: "Mises à jour")

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Whispeur \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.9))
                            Text("Les mises à jour incluent le moteur whisper.cpp intégré.")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.35))
                        }
                        Spacer()
                        Button("Vérifier…") {
                            UpdaterService.shared.checkForUpdates()
                        }
                    }
                }
            }
```

- [ ] **Step 5 : Régénérer, builder, vérifier**

```bash
xcodegen generate
xcodebuild -project Whispeur.xcodeproj -scheme Whispeur -configuration Release build SYMROOT="$PWD/build"
xcodebuild -project Whispeur.xcodeproj -scheme WhispeurTests test -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData
```

Attendu : BUILD SUCCEEDED (la première fois, xcodebuild résout le package Sparkle — accès réseau requis, hors sandbox) + tests PASS.

Vérifier l'embarquement du framework :

```bash
codesign -dv build/Release/Whispeur.app/Contents/Frameworks/Sparkle.framework 2>&1 | head -3
```

Attendu : le framework existe et est signé (ad-hoc, re-signé par Xcode).

Vérification manuelle : lancer l'app, menu barre → « Vérifier les mises à jour… » → Sparkle affiche une erreur de chargement d'appcast (normal : aucune release publiée) — cela prouve que l'updater fonctionne.

- [ ] **Step 6 : Commit**

```bash
git add project.yml Whispeur/Services/UpdaterService.swift Whispeur/App/WhispeurApp.swift Whispeur/Views/StatusBarController.swift Whispeur/Views/GeneralSection.swift Makefile .gitignore
git commit -m "feat: integrate Sparkle 2 auto-updates with GitHub Releases feed"
```

---

### Task 6 : Pipeline de release (`make release`)

**Files:**
- Create: `scripts/release.sh` (exécutable)
- Modify: `Makefile`
- Create: `docs/RELEASING.md`

**Interfaces:**
- Consumes: `make dmg` existant, `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` (Task 5), outils Sparkle dans `tools/sparkle/bin/` (Task 5).

- [ ] **Step 1 : Créer le script de release**

`scripts/release.sh` :

```bash
#!/usr/bin/env bash
# Release Whispeur : bump version, build, DMG, appcast signé, GitHub Release.
# Usage : scripts/release.sh 1.0.1
set -euo pipefail

VERSION="${1:?Usage: scripts/release.sh <version>  (ex: 1.0.1)}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

command -v gh >/dev/null || { echo "❌ gh CLI requis : brew install gh && gh auth login"; exit 1; }
[ -x tools/sparkle/bin/generate_appcast ] || { echo "❌ Outils Sparkle manquants : make sparkle-tools"; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "❌ Working tree non propre — committe d'abord."; exit 1; }

# 1. Bump des versions dans project.yml (CFBundleVersion = nb de commits).
BUILD_NUMBER="$(git rev-list --count HEAD)"
/usr/bin/sed -i '' "s/MARKETING_VERSION: \".*\"/MARKETING_VERSION: \"$VERSION\"/" project.yml
/usr/bin/sed -i '' "s/CURRENT_PROJECT_VERSION: \".*\"/CURRENT_PROJECT_VERSION: \"$BUILD_NUMBER\"/" project.yml

# 2. Build + DMG (make dmg regénère le projet via setup).
make dmg

# 3. Appcast signé (EdDSA depuis le Keychain). Seule la dernière version est
#    publiée dans l'appcast : le dossier ne contient qu'un DMG.
mkdir -p releases
rm -f releases/*.dmg releases/appcast.xml
cp Whispeur.dmg "releases/Whispeur-$VERSION.dmg"
tools/sparkle/bin/generate_appcast releases \
    --download-url-prefix "https://github.com/emilienrk/whispeur/releases/download/v$VERSION/" \
    --maximum-deltas 0

# 4. Commit du bump + tag.
git add project.yml
git commit -m "chore: release v$VERSION"
git tag "v$VERSION"
git push origin main "v$VERSION"

# 5. GitHub Release avec DMG + appcast (l'URL /releases/latest/download/appcast.xml
#    utilisée par SUFeedURL pointe toujours sur la dernière release).
gh release create "v$VERSION" \
    "releases/Whispeur-$VERSION.dmg" \
    releases/appcast.xml \
    --title "Whispeur $VERSION" \
    --generate-notes

echo "✅ Release v$VERSION publiée."
```

Puis : `chmod +x scripts/release.sh`

- [ ] **Step 2 : Ajouter le target Makefile**

Dans `Makefile`, mettre à jour `.PHONY` et ajouter :

```make
.PHONY: build dmg clean setup sparkle-tools release

release: sparkle-tools
	./scripts/release.sh $(VERSION)
```

- [ ] **Step 3 : Documenter la procédure**

`docs/RELEASING.md` :

```markdown
# Publier une release Whispeur

## Prérequis (une seule fois)

1. `brew install gh && gh auth login`
2. `make sparkle-tools`
3. `./tools/sparkle/bin/generate_keys` — la clé privée EdDSA vit dans le
   Keychain de cette machine ; la clé publique doit être dans `project.yml`
   (`SUPublicEDKey`). **Sans la clé privée, impossible de signer les updates.**

## À chaque release

```bash
make release VERSION=1.0.1
```

Le script : bump les versions dans `project.yml`, build le DMG, génère
`appcast.xml` signé, committe + tag `v1.0.1`, pousse, et crée la GitHub
Release avec le DMG et l'appcast en assets.

Les apps installées vérifient
`https://github.com/emilienrk/whispeur/releases/latest/download/appcast.xml`.

## Notes

- App signée ad-hoc : les mises à jour Sparkle passent (validation EdDSA),
  seul le premier téléchargement manuel du DMG affiche l'avertissement
  Gatekeeper.
- `CFBundleVersion` = `git rev-list --count HEAD` (croissant, Sparkle
  compare cette valeur).
```

- [ ] **Step 4 : Vérifier le script à sec**

```bash
bash -n scripts/release.sh
make -n release VERSION=9.9.9 | head -5
```

Attendu : `bash -n` silencieux (syntaxe OK) ; `make -n` affiche l'appel à `scripts/release.sh 9.9.9` sans l'exécuter.

- [ ] **Step 5 : Commit**

```bash
git add scripts/release.sh Makefile docs/RELEASING.md
git commit -m "feat: add make release pipeline with signed Sparkle appcast"
```

- [ ] **Step 6 : Release de test de bout en bout (manuel, avec l'utilisateur)**

Publier une vraie release `make release VERSION=1.0.0`, installer le DMG, puis publier `1.0.1` et vérifier que l'app installée propose la mise à jour. Cette étape nécessite le Keychain et `gh auth` — à faire avec l'utilisateur en session interactive.
