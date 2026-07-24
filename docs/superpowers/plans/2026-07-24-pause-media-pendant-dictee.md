# Pause/reprise automatique de la musique pendant la dictée — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Mettre en pause ce qui joue (Spotify, Apple Music, YouTube, VLC…) quand une dictée démarre, puis le relancer à la fin de l'enregistrement, avec un réglage activé par défaut.

**Architecture:** Un service isolé `MediaPlaybackController` sonde CoreAudio (`kAudioDevicePropertyDeviceIsRunningSomewhere` sur la sortie par défaut) et pilote la touche média `NX_KEYTYPE_PLAY` via `CGEvent`. Sonde et émetteur sont derrière protocole, ce qui rend toute la logique testable sans son ni matériel. `RecordingCoordinator` appelle la pause avant d'ouvrir le micro et la reprise sur toutes les sorties du pipeline.

**Tech Stack:** Swift 6, SwiftUI, `@Observable`, CoreAudio, AppKit (`NSEvent`/`CGEvent`), Swift Testing, xcodegen.

**Spec:** `docs/superpowers/specs/2026-07-24-pause-media-pendant-dictee-design.md`

## Global Constraints

- Swift 6 en concurrence stricte. Tout le code de cette feature est `@MainActor`, y compris les deux protocoles — sans ça les fakes de test (`@MainActor final class`) ne peuvent pas s'y conformer.
- Le projet est généré par **xcodegen** : après tout ajout de fichier source, relancer `xcodegen generate`, sinon le fichier n'est pas dans le target.
- Le target `WhispeurTests` **liste ses sources fichier par fichier** dans `project.yml`. Un nouveau fichier de `Whispeur/Services/` doit y être ajouté explicitement.
- `xcodebuild` échoue sous le sandbox de l'agent (« Operation not permitted » sur DerivedData) → lancer les builds avec `dangerouslyDisableSandbox: true`.
- Commande de test : `xcodebuild -project Whispeur.xcodeproj -scheme WhispeurTests test -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData`
- Commentaires **en anglais**, densité faible, uniquement là où le *pourquoi* n'est pas évident. Chaînes UI **en français** (langue source), traduites en anglais dans `Localizable.xcstrings`.
- Ne jamais envoyer la touche Play sans preuve que le son s'est arrêté — c'est l'invariant central de la feature.

---

### Task 1: Réglage `pauseMediaWhileRecording`

**Files:**
- Modify: `Whispeur/Models/AppSettings.swift:37` (bloc d'init) et `:140` (après `confirmationSoundEnabled`)
- Test: `WhispeurTests/EngineConfigTests.swift`

**Interfaces:**
- Consumes: rien
- Produces: `AppSettings.pauseMediaWhileRecording: Bool` (défaut `true`, clé UserDefaults `"pauseMediaWhileRecording"`)

- [ ] **Step 1: Écrire le test qui échoue**

Ajouter à la fin de la struct `EngineConfigTests` dans `WhispeurTests/EngineConfigTests.swift`. Le pattern sauvegarde/restaure la valeur, comme les tests existants, parce que `AppSettings.shared` écrit dans les vraies préférences.

```swift
    @Test("pauseMediaWhileRecording round-trips through UserDefaults")
    func pauseMediaWhileRecordingPersists() {
        let s = AppSettings.shared
        let saved = s.pauseMediaWhileRecording
        defer { s.pauseMediaWhileRecording = saved }

        s.pauseMediaWhileRecording = false
        #expect(s.pauseMediaWhileRecording == false)
        #expect(UserDefaults.standard.bool(forKey: "pauseMediaWhileRecording") == false)

        s.pauseMediaWhileRecording = true
        #expect(s.pauseMediaWhileRecording == true)
        #expect(UserDefaults.standard.bool(forKey: "pauseMediaWhileRecording") == true)
    }
```

- [ ] **Step 2: Lancer le test pour vérifier qu'il échoue**

Run (avec `dangerouslyDisableSandbox: true`) :
```bash
xcodebuild -project Whispeur.xcodeproj -scheme WhispeurTests test -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData
```
Expected: échec de **compilation** — `value of type 'AppSettings' has no member 'pauseMediaWhileRecording'`.

- [ ] **Step 3: Ajouter la lecture dans l'init**

Dans `Whispeur/Models/AppSettings.swift`, juste après la ligne `_confirmationSound = (ud.object(forKey: "confirmationSound") as? Bool) ?? false` :

```swift
        _pauseMediaWhileRecording = (ud.object(forKey: "pauseMediaWhileRecording") as? Bool) ?? true
```

- [ ] **Step 4: Ajouter la propriété**

Dans la section `// MARK: - General settings`, juste après le bloc `confirmationSoundEnabled` :

```swift
    private var _pauseMediaWhileRecording: Bool {
        didSet { UserDefaults.standard.set(_pauseMediaWhileRecording, forKey: "pauseMediaWhileRecording") }
    }
    /// Pause whatever is playing while a dictation runs, then resume it afterwards.
    var pauseMediaWhileRecording: Bool {
        get { _pauseMediaWhileRecording }
        set { _pauseMediaWhileRecording = newValue }
    }
```

- [ ] **Step 5: Lancer le test pour vérifier qu'il passe**

Run (avec `dangerouslyDisableSandbox: true`) :
```bash
xcodebuild -project Whispeur.xcodeproj -scheme WhispeurTests test -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData
```
Expected: PASS, y compris tous les tests existants.

- [ ] **Step 6: Commit**

```bash
git add Whispeur/Models/AppSettings.swift WhispeurTests/EngineConfigTests.swift
git commit -m "feat(settings): add pauseMediaWhileRecording preference"
```

---

### Task 2: `MediaPlaybackController` et sa logique de décision

**Files:**
- Create: `Whispeur/Services/MediaPlaybackController.swift`
- Create: `WhispeurTests/MediaPlaybackControllerTests.swift`
- Modify: `project.yml` (sources du target `WhispeurTests`)

**Interfaces:**
- Consumes: `AppSettings.pauseMediaWhileRecording` (Task 1) — mais uniquement via une closure injectée, le contrôleur ne référence pas `AppSettings` directement.
- Produces:
  - `@MainActor protocol SystemAudioProbe { var isOutputActive: Bool { get } }`
  - `@MainActor protocol MediaKeySender { func sendPlayPause() }`
  - `@MainActor final class MediaPlaybackController`
    - `init(probe: SystemAudioProbe, keySender: MediaKeySender, isEnabled: @escaping @MainActor () -> Bool, resumeSettleDelay: Duration = .milliseconds(120))`
    - `func pauseForRecording()`
    - `func resumeAfterRecording() async`
    - `private(set) var didPause: Bool`

Cette tâche ne crée **que** la logique et les protocoles. Les implémentations réelles (CoreAudio, CGEvent) arrivent en Task 3 : la logique se teste entièrement sans elles.

- [ ] **Step 1: Déclarer le nouveau fichier au target de test**

Dans `project.yml`, target `WhispeurTests`, section `sources`, ajouter après la ligne `- path: Whispeur/Services/HotkeyManager.swift` :

```yaml
      - path: Whispeur/Services/MediaPlaybackController.swift
```

Puis, dans `OTHER_LDFLAGS` des **deux** targets (`Whispeur` et `WhispeurTests`), ajouter après `- "-framework AVFoundation"` :

```yaml
          - "-framework CoreAudio"
```

Régénérer le projet :
```bash
xcodegen generate
```

- [ ] **Step 2: Écrire les tests qui échouent**

Créer `WhispeurTests/MediaPlaybackControllerTests.swift`. Le fake de sonde renvoie une file de lectures préprogrammées : c'est ce qui permet de simuler « ça jouait, puis c'est devenu silencieux » sans matériel. `resumeSettleDelay: .zero` évite d'attendre 120 ms par test.

```swift
// MediaPlaybackControllerTests.swift
// WhispeurTests

import Testing

@MainActor
private final class FakeAudioProbe: SystemAudioProbe {
    private var readings: [Bool]
    private(set) var readCount = 0

    init(_ readings: [Bool]) { self.readings = readings }

    var isOutputActive: Bool {
        readCount += 1
        return readings.isEmpty ? false : readings.removeFirst()
    }
}

@MainActor
private final class FakeMediaKeySender: MediaKeySender {
    private(set) var sendCount = 0
    func sendPlayPause() { sendCount += 1 }
}

@MainActor
private func makeController(
    readings: [Bool],
    enabled: Bool = true
) -> (MediaPlaybackController, FakeAudioProbe, FakeMediaKeySender) {
    let probe = FakeAudioProbe(readings)
    let sender = FakeMediaKeySender()
    let controller = MediaPlaybackController(
        probe: probe,
        keySender: sender,
        isEnabled: { enabled },
        resumeSettleDelay: .zero
    )
    return (controller, probe, sender)
}

@MainActor
struct MediaPlaybackControllerTests {

    @Test("Nothing playing: no media key is ever sent")
    func silentSystemSendsNothing() async {
        let (controller, _, sender) = makeController(readings: [false])
        controller.pauseForRecording()
        #expect(controller.didPause == false)
        #expect(sender.sendCount == 0)

        await controller.resumeAfterRecording()
        #expect(sender.sendCount == 0)
    }

    @Test("Music playing then silent: pause then resume")
    func musicIsPausedAndResumed() async {
        let (controller, _, sender) = makeController(readings: [true, false])
        controller.pauseForRecording()
        #expect(controller.didPause == true)
        #expect(sender.sendCount == 1)

        await controller.resumeAfterRecording()
        #expect(controller.didPause == false)
        #expect(sender.sendCount == 2)
    }

    @Test("Zoom call: sound never stopped, so no resume key is sent")
    func stillPlayingAtResumeSendsNoPlay() async {
        let (controller, _, sender) = makeController(readings: [true, true])
        controller.pauseForRecording()
        #expect(sender.sendCount == 1)

        await controller.resumeAfterRecording()
        #expect(sender.sendCount == 1)
        #expect(controller.didPause == false)
    }

    @Test("Setting disabled: the probe is never even read")
    func disabledSettingIsInert() async {
        let (controller, probe, sender) = makeController(readings: [true, false], enabled: false)
        controller.pauseForRecording()
        await controller.resumeAfterRecording()

        #expect(probe.readCount == 0)
        #expect(sender.sendCount == 0)
        #expect(controller.didPause == false)
    }

    @Test("Resume called twice sends a single play key")
    func doubleResumeIsIdempotent() async {
        let (controller, _, sender) = makeController(readings: [true, false, false])
        controller.pauseForRecording()
        await controller.resumeAfterRecording()
        await controller.resumeAfterRecording()

        #expect(sender.sendCount == 2)
    }

    @Test("Resume without a preceding pause does nothing")
    func resumeWithoutPauseIsNoOp() async {
        let (controller, probe, sender) = makeController(readings: [false])
        await controller.resumeAfterRecording()

        #expect(probe.readCount == 0)
        #expect(sender.sendCount == 0)
    }
}
```

- [ ] **Step 3: Lancer les tests pour vérifier qu'ils échouent**

Run (avec `dangerouslyDisableSandbox: true`) :
```bash
xcodebuild -project Whispeur.xcodeproj -scheme WhispeurTests test -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData
```
Expected: échec de compilation — `cannot find type 'SystemAudioProbe' in scope`.

- [ ] **Step 4: Écrire le contrôleur**

Créer `Whispeur/Services/MediaPlaybackController.swift` :

```swift
// MediaPlaybackController.swift
// Whispeur
//
// Pauses whatever is playing while a dictation runs, then resumes it.
//
// The Play/Pause media key is a blind toggle: nothing tells us whether a player
// actually received it. So we only send Play once we have proof the sound
// stopped — otherwise ending a Zoom call would start Spotify out of nowhere.
//
// Both CoreAudio readings happen while the microphone is closed (before capture
// starts, and after it stops). On AirPods or any device that is both input and
// output, a reading taken during capture would always report "running" because
// of our own microphone, and the music would never resume.

import Foundation

// MARK: - Injected dependencies

@MainActor
protocol SystemAudioProbe {
    /// Whether the default output device is currently performing I/O.
    var isOutputActive: Bool { get }
}

@MainActor
protocol MediaKeySender {
    func sendPlayPause()
}

// MARK: - Controller

@MainActor
final class MediaPlaybackController {

    private let probe: SystemAudioProbe
    private let keySender: MediaKeySender
    private let isEnabled: @MainActor () -> Bool
    private let resumeSettleDelay: Duration

    /// True while a player is paused *by us* and is owed a resume.
    private(set) var didPause = false

    init(
        probe: SystemAudioProbe,
        keySender: MediaKeySender,
        isEnabled: @escaping @MainActor () -> Bool,
        resumeSettleDelay: Duration = .milliseconds(120)
    ) {
        self.probe = probe
        self.keySender = keySender
        self.isEnabled = isEnabled
        self.resumeSettleDelay = resumeSettleDelay
    }

    /// Call before opening the microphone, so the probe reading is not polluted
    /// by our own capture device.
    func pauseForRecording() {
        guard isEnabled(), probe.isOutputActive else {
            didPause = false
            return
        }
        keySender.sendPlayPause()
        didPause = true
    }

    /// Safe to call from every pipeline exit path — errors included. The
    /// `didPause` guard makes repeated calls no-ops.
    func resumeAfterRecording() async {
        guard didPause else { return }
        didPause = false

        try? await Task.sleep(for: resumeSettleDelay)

        // Sound still coming out means nobody obeyed our pause (a call app), or
        // another source is talking over it. Either way, sending Play would
        // start something the user never asked for.
        guard !probe.isOutputActive else { return }
        keySender.sendPlayPause()
    }
}
```

- [ ] **Step 5: Lancer les tests pour vérifier qu'ils passent**

Run (avec `dangerouslyDisableSandbox: true`) :
```bash
xcodebuild -project Whispeur.xcodeproj -scheme WhispeurTests test -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData
```
Expected: PASS — les 6 nouveaux tests plus tous les existants.

- [ ] **Step 6: Commit**

```bash
git add Whispeur/Services/MediaPlaybackController.swift WhispeurTests/MediaPlaybackControllerTests.swift project.yml Whispeur.xcodeproj
git commit -m "feat(media): add MediaPlaybackController pause/resume logic"
```

---

### Task 3: Implémentations réelles CoreAudio et touche média

**Files:**
- Modify: `Whispeur/Services/MediaPlaybackController.swift` (ajout en fin de fichier)

**Interfaces:**
- Consumes: `SystemAudioProbe`, `MediaKeySender` (Task 2)
- Produces: `struct CoreAudioOutputProbe: SystemAudioProbe`, `struct SystemMediaKeySender: MediaKeySender`

Ces deux types touchent le matériel et le serveur de fenêtres : ils ne sont pas couverts par des tests unitaires, ce qui est justement la raison d'être des protocoles de la Task 2. La vérification ici est la compilation plus un test manuel.

- [ ] **Step 1: Ajouter les imports**

En haut de `Whispeur/Services/MediaPlaybackController.swift`, remplacer `import Foundation` par :

```swift
import Foundation
import AppKit
import CoreAudio
```

- [ ] **Step 2: Écrire la sonde CoreAudio**

Ajouter à la fin de `Whispeur/Services/MediaPlaybackController.swift` :

```swift
// MARK: - Real implementations

/// Reports whether the default output device is performing I/O.
/// Any CoreAudio failure is reported as "silent" so Whispeur stays passive.
struct CoreAudioOutputProbe: SystemAudioProbe {

    var isOutputActive: Bool {
        guard let device = defaultOutputDevice() else { return false }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var isRunning: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &isRunning)

        guard status == noErr else { return false }
        return isRunning != 0
    }

    private func defaultOutputDevice() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        )

        guard status == noErr, deviceID != AudioObjectID(kAudioObjectUnknown) else { return nil }
        return deviceID
    }
}
```

- [ ] **Step 3: Écrire l'émetteur de touche média**

Ajouter à la suite, dans le même fichier :

```swift
/// Posts the system Play/Pause media key. Uses the same CGEvent path as
/// ClipboardService, so the Accessibility permission the app already holds is
/// enough — no new prompt.
struct SystemMediaKeySender: MediaKeySender {

    /// NX_KEYTYPE_PLAY from IOKit's hidsystem/ev_keymap.h.
    private static let playPauseKey: Int32 = 16

    func sendPlayPause() {
        post(keyDown: true)
        post(keyDown: false)
    }

    private func post(keyDown: Bool) {
        let state: Int32 = keyDown ? 0xA : 0xB
        let data1 = Int((Self.playPauseKey << 16) | (state << 8))
        let flags = NSEvent.ModifierFlags(rawValue: keyDown ? 0xA00 : 0xB00)

        guard let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: data1,
            data2: -1
        ) else { return }

        event.cgEvent?.post(tap: .cghidEventTap)
    }
}
```

- [ ] **Step 4: Vérifier que tout compile et que les tests passent toujours**

Run (avec `dangerouslyDisableSandbox: true`) :
```bash
xcodebuild -project Whispeur.xcodeproj -scheme WhispeurTests test -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData
```
Expected: PASS. Si le linker se plaint de symboles `AudioObject*` manquants, c'est que `-framework CoreAudio` n'a pas été ajouté aux deux targets en Task 2 Step 1, ou que `xcodegen generate` n'a pas été relancé.

- [ ] **Step 5: Commit**

```bash
git add Whispeur/Services/MediaPlaybackController.swift
git commit -m "feat(media): add CoreAudio probe and media key sender"
```

---

### Task 4: Branchement dans le pipeline d'enregistrement

**Files:**
- Modify: `Whispeur/Services/RecordingCoordinator.swift:47-51` (services), `:71-85` (init), `:123-154` (`startPipeline`), `:157-169` (`finishRecording`), `:227-238` (`setError`)
- Modify: `Whispeur/App/WhispeurApp.swift:25-43` (`ServicesContainer`)

**Interfaces:**
- Consumes: `MediaPlaybackController` (Task 2), `CoreAudioOutputProbe` / `SystemMediaKeySender` (Task 3), `AppSettings.pauseMediaWhileRecording` (Task 1)
- Produces: `RecordingCoordinator.init` gagne un paramètre `mediaPlayback: MediaPlaybackController` en dernière position.

- [ ] **Step 1: Ajouter la dépendance au coordinator**

Dans `Whispeur/Services/RecordingCoordinator.swift`, section `// MARK: Services (injected)`, après `let historyService: HistoryService` :

```swift
    let mediaPlayback: MediaPlaybackController
```

Dans l'init, ajouter le paramètre en dernière position et son assignation :

```swift
    init(
        hotkeyManager: HotkeyManager,
        audioCapture: AudioCaptureService,
        whisperService: WhisperService,
        clipboardService: ClipboardService,
        historyService: HistoryService,
        mediaPlayback: MediaPlaybackController
    ) {
        self.hotkeyManager  = hotkeyManager
        self.audioCapture   = audioCapture
        self.whisperService = whisperService
        self.clipboardService = clipboardService
        self.historyService = historyService
        self.mediaPlayback  = mediaPlayback

        configureHotkeyCallbacks()
    }
```

- [ ] **Step 2: Mettre en pause avant d'ouvrir le micro**

Dans `startPipeline()`, insérer l'appel juste avant le commentaire `// --- Start audio immediately ---`, donc après l'annulation de `unloadTask` :

```swift
        // Pause before the mic opens: once capture runs, a shared input/output
        // device (AirPods) would read as "playing" no matter what.
        mediaPlayback.pauseForRecording()

        // --- Start audio immediately ---
        do {
            try audioCapture.startRecording()
        } catch {
            setError("Micro : \(error.localizedDescription)")
            return
        }
```

- [ ] **Step 3: Relancer à la fin de l'enregistrement**

Dans `finishRecording()`, juste après `let samples = audioCapture.stopRecording()` :

```swift
        let samples = audioCapture.stopRecording()

        // Resume right away rather than after transcription — a large model can
        // take seconds, and the silence is noticeable.
        Task { await mediaPlayback.resumeAfterRecording() }
```

- [ ] **Step 4: Relancer aussi sur les chemins d'erreur**

Dans `setError(_:)`, juste après la ligne `logger.error("Pipeline error: \(message)")` :

```swift
        Task { await mediaPlayback.resumeAfterRecording() }
```

Cela couvre l'échec du micro, l'échec de chargement du modèle et l'échec de transcription. L'appel est inoffensif si aucune pause n'a eu lieu.

- [ ] **Step 5: Câbler le service dans l'app**

Dans `Whispeur/App/WhispeurApp.swift`, dans `ServicesContainer`, après `let clipboardService = ClipboardService()` :

```swift
    let mediaPlayback = MediaPlaybackController(
        probe: CoreAudioOutputProbe(),
        keySender: SystemMediaKeySender(),
        isEnabled: { AppSettings.shared.pauseMediaWhileRecording }
    )
```

Puis passer le service au coordinator dans le `lazy var` :

```swift
    private(set) lazy var coordinator: RecordingCoordinator = {
        RecordingCoordinator(
            hotkeyManager: hotkeyManager,
            audioCapture: audioCapture,
            whisperService: whisperService,
            clipboardService: clipboardService,
            historyService: historyService,
            mediaPlayback: mediaPlayback
        )
    }()
```

- [ ] **Step 6: Lancer les tests**

Run (avec `dangerouslyDisableSandbox: true`) :
```bash
xcodebuild -project Whispeur.xcodeproj -scheme WhispeurTests test -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData
```
Expected: PASS. `RecordingCoordinator.swift` fait partie des sources du target de test, donc la signature d'init doit compiler ; aucun test existant ne construit un coordinator, il n'y a donc rien à corriger dans `PipelineStateTests`. Si un appel de construction apparaît malgré tout, lui ajouter l'argument `mediaPlayback:` avec un contrôleur bâti sur les fakes de `MediaPlaybackControllerTests`.

- [ ] **Step 7: Commit**

```bash
git add Whispeur/Services/RecordingCoordinator.swift Whispeur/App/WhispeurApp.swift
git commit -m "feat(pipeline): pause media during dictation and resume after"
```

---

### Task 5: Toggle dans les réglages et traductions

**Files:**
- Modify: `Whispeur/Views/GeneralSection.swift:64-84` (carte « Comportement »)
- Modify: `Whispeur/Localizable.xcstrings`

**Interfaces:**
- Consumes: `AppSettings.pauseMediaWhileRecording` (Task 1)
- Produces: rien pour les tâches suivantes

- [ ] **Step 1: Ajouter le toggle**

Dans `Whispeur/Views/GeneralSection.swift`, dans la `SettingsCard` « Comportement », après le `SettingsToggleRow` « Son de confirmation » :

```swift
                    Divider().opacity(0.08)

                    SettingsToggleRow(
                        icon: "pause.circle.fill",
                        label: "Mettre la musique en pause",
                        description: "Coupe la lecture en cours pendant la dictée, puis la relance.",
                        isOn: $settings.pauseMediaWhileRecording
                    )
```

- [ ] **Step 2: Ajouter les traductions anglaises**

`Localizable.xcstrings` est un JSON dont la langue source est le français. Ajouter les deux entrées :

```bash
jq --indent 2 --sort-keys '
  .strings["Mettre la musique en pause"] = {
    "extractionState": "manual",
    "localizations": {
      "en": { "stringUnit": { "state": "translated", "value": "Pause music while dictating" } }
    }
  } |
  .strings["Coupe la lecture en cours pendant la dictée, puis la relance."] = {
    "extractionState": "manual",
    "localizations": {
      "en": { "stringUnit": { "state": "translated", "value": "Pauses whatever is playing during dictation, then resumes it." } }
    }
  }
' Whispeur/Localizable.xcstrings > /tmp/xcstrings.json && mv /tmp/xcstrings.json Whispeur/Localizable.xcstrings
```

Vérifier que le fichier est toujours du JSON valide et contient bien 81 entrées :
```bash
jq '.strings | length' Whispeur/Localizable.xcstrings
```
Expected: `81`

- [ ] **Step 3: Builder l'app complète**

Run (avec `dangerouslyDisableSandbox: true`) :
```bash
xcodebuild -project Whispeur.xcodeproj -scheme Whispeur -configuration Debug build -derivedDataPath build/DerivedData
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Lancer les tests**

Run (avec `dangerouslyDisableSandbox: true`) :
```bash
xcodebuild -project Whispeur.xcodeproj -scheme WhispeurTests test -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Whispeur/Views/GeneralSection.swift Whispeur/Localizable.xcstrings
git commit -m "feat(settings): add pause-media toggle to General section"
```

---

## Vérification manuelle finale

Les tests unitaires couvrent la logique de décision, pas le dialogue réel avec CoreAudio ni la touche média. Ces quatre scénarios sont à passer à la main sur l'app buildée, une fois les 5 tâches terminées :

1. **Spotify ou YouTube en lecture** → dicter : la musique se coupe à l'appui, repart au relâchement.
2. **Rien qui joue** → dicter : aucun lecteur ne démarre, ni pendant ni après.
3. **Appel visio (ou une vidéo dans une app qui ignore les touches média)** → dicter : le son de l'appel continue, et surtout **aucun lecteur ne démarre à la fin**.
4. **Toggle désactivé dans les réglages, musique en lecture** → dicter : la musique n'est pas touchée.

Le point 3 est le plus important : c'est l'invariant de sécurité de la feature.

Bonus si un casque Bluetooth est disponible : refaire le point 1 avec des AirPods, pour valider que la lecture CoreAudio après fermeture du micro n'est pas polluée par la capture.
