# Onboarding de premier lancement — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Qu'un utilisateur qui ouvre Whispeur pour la première fois arrive à sa première dictée réussie sans jamais toucher aux réglages, au lieu de tomber sur « Aucun modèle Whisper sélectionné ».

**Architecture:** Une machine à états `OnboardingFlow` (`Whispeur/Models/`) séquence six étapes et ne connaît ni l'UI ni le système : ce que macOS accorde réellement entre par un protocole `OnboardingRequirements` injecté, ce qui rend toute la progression testable sans permission ni téléchargement. Une fenêtre dédiée, calquée sur `SettingsWindowController`, affiche une page par étape et réutilise les services existants (`MicrophonePermissionManager`, `ModelManager`, `RecordingCoordinator`).

**Tech Stack:** Swift 6, SwiftUI, `@Observable`, AppKit (`NSWindow`), Swift Testing, xcodegen.

## Global Constraints

- Swift 6 en concurrence stricte. Tout le code de cette feature est `@MainActor`, y compris le protocole `OnboardingRequirements` — sans ça le fake de test (`@MainActor final class`) ne peut pas s'y conformer.
- Le projet est généré par **xcodegen** : après tout ajout de fichier source, relancer `xcodegen generate`, sinon le fichier n'est pas dans le target.
- Le target `WhispeurTests` liste les fichiers de `Whispeur/Services/` **un par un** dans `project.yml`, mais inclut **`Whispeur/Models` en entier**. C'est la raison pour laquelle `OnboardingFlow.swift` va dans `Models/` : aucune modification de `project.yml` n'est nécessaire.
- `xcodebuild` échoue sous le sandbox de l'agent (« Operation not permitted » sur DerivedData) → lancer les builds avec `dangerouslyDisableSandbox: true`.
- Commande de test : `xcodebuild -project Whispeur.xcodeproj -scheme WhispeurTests test -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData`
- Commentaires **en anglais**, densité faible, uniquement là où le *pourquoi* n'est pas évident. Chaînes UI **en français** (langue source), traduites en anglais dans `Localizable.xcstrings`.
- Modèle proposé par défaut : `large-v3-turbo-q5_0` (547 MiB). Repli connexion lente : `base-q5_1` (57 MiB). Ces deux noms doivent correspondre exactement à `WhisperModelDescriptor.catalog` (`Whispeur/Models/WhisperModel.swift:121` et `:139`).
- L'onboarding ne doit jamais **bloquer** sur l'Accessibilité : sans elle, le texte est copié dans le presse-papier, ce qui reste utilisable. Le micro et le modèle, eux, sont bloquants.

---

### Task 1: Flag `hasCompletedOnboarding`

**Files:**
- Modify: `Whispeur/Models/AppSettings.swift` (bloc d'init, puis section `// MARK: - General settings`)
- Test: `WhispeurTests/EngineConfigTests.swift`

**Interfaces:**
- Consumes: rien
- Produces: `AppSettings.hasCompletedOnboarding: Bool` (défaut `false`, clé UserDefaults `"hasCompletedOnboarding"`)

- [ ] **Step 1: Écrire le test qui échoue**

Ajouter à la fin de la struct `EngineConfigTests` dans `WhispeurTests/EngineConfigTests.swift`. Le pattern sauvegarde/restaure la valeur, comme les tests existants, parce que `AppSettings.shared` écrit dans les vraies préférences.

```swift
    @Test("hasCompletedOnboarding round-trips through UserDefaults")
    func onboardingFlagPersists() {
        let s = AppSettings.shared
        let saved = s.hasCompletedOnboarding
        defer { s.hasCompletedOnboarding = saved }

        s.hasCompletedOnboarding = true
        #expect(s.hasCompletedOnboarding == true)
        #expect(UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") == true)

        s.hasCompletedOnboarding = false
        #expect(s.hasCompletedOnboarding == false)
        #expect(UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") == false)
    }
```

- [ ] **Step 2: Lancer le test pour vérifier qu'il échoue**

Run (avec `dangerouslyDisableSandbox: true`) :
```bash
xcodebuild -project Whispeur.xcodeproj -scheme WhispeurTests test -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData
```
Expected: échec de **compilation** — `value of type 'AppSettings' has no member 'hasCompletedOnboarding'`.

- [ ] **Step 3: Ajouter la lecture dans l'init**

Dans `Whispeur/Models/AppSettings.swift`, juste après la ligne `_vadEnabled = (ud.object(forKey: "vadEnabled") as? Bool) ?? false` :

```swift
        _hasCompletedOnboarding = (ud.object(forKey: "hasCompletedOnboarding") as? Bool) ?? false
```

- [ ] **Step 4: Ajouter la propriété**

Dans la section `// MARK: - General settings`, après le bloc `pauseMediaWhileRecording` :

```swift
    private var _hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(_hasCompletedOnboarding, forKey: "hasCompletedOnboarding") }
    }
    /// False until the first-launch setup has been walked through or dismissed.
    var hasCompletedOnboarding: Bool {
        get { _hasCompletedOnboarding }
        set { _hasCompletedOnboarding = newValue }
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
git commit -m "feat(settings): add hasCompletedOnboarding preference"
```

---

### Task 2: Machine à états `OnboardingFlow`

**Files:**
- Create: `Whispeur/Models/OnboardingFlow.swift`
- Create: `WhispeurTests/OnboardingFlowTests.swift`

**Interfaces:**
- Consumes: rien (le protocole isole entièrement le système)
- Produces:
  - `enum OnboardingStep: Int, CaseIterable, Comparable, Sendable` — cas `welcome`, `microphone`, `accessibility`, `model`, `hotkey`, `done`
  - `@MainActor protocol OnboardingRequirements { var isMicrophoneGranted: Bool { get }; var isAccessibilityGranted: Bool { get }; var hasUsableModel: Bool { get } }`
  - `@MainActor @Observable final class OnboardingFlow`
    - `init(requirements: any OnboardingRequirements)`
    - `private(set) var step: OnboardingStep`
    - `var canAdvance: Bool`
    - `func advance()`
    - `func back()`

Cette tâche ne crée **que** la logique. Les implémentations réelles (AVFoundation, AX, système de fichiers) arrivent en Task 3.

`Whispeur/Models` est inclus en entier dans le target de test : aucun ajout à `project.yml`, mais `xcodegen generate` reste nécessaire pour que le nouveau fichier entre dans les deux targets.

- [ ] **Step 1: Écrire les tests qui échouent**

Créer `WhispeurTests/OnboardingFlowTests.swift`. Le fake expose des booléens mutables, ce qui permet de simuler « l'utilisateur vient d'accorder le micro » entre deux appels.

```swift
// OnboardingFlowTests.swift
// WhispeurTests

import Testing

@MainActor
private final class FakeRequirements: OnboardingRequirements {
    var isMicrophoneGranted: Bool
    var isAccessibilityGranted: Bool
    var hasUsableModel: Bool

    init(mic: Bool = false, accessibility: Bool = false, model: Bool = false) {
        self.isMicrophoneGranted = mic
        self.isAccessibilityGranted = accessibility
        self.hasUsableModel = model
    }
}

@MainActor
struct OnboardingFlowTests {

    @Test("A fresh flow starts on the welcome step")
    func startsOnWelcome() {
        let flow = OnboardingFlow(requirements: FakeRequirements())
        #expect(flow.step == .welcome)
        #expect(flow.canAdvance == true)
    }

    @Test("Microphone blocks until it is granted")
    func microphoneIsBlocking() {
        let requirements = FakeRequirements()
        let flow = OnboardingFlow(requirements: requirements)

        flow.advance()
        #expect(flow.step == .microphone)
        #expect(flow.canAdvance == false)

        flow.advance()
        #expect(flow.step == .microphone)

        requirements.isMicrophoneGranted = true
        #expect(flow.canAdvance == true)
        flow.advance()
        #expect(flow.step == .accessibility)
    }

    @Test("Accessibility can be skipped: it only degrades auto-paste")
    func accessibilityIsOptional() {
        let requirements = FakeRequirements(mic: true)
        let flow = OnboardingFlow(requirements: requirements)
        flow.advance()

        #expect(flow.step == .accessibility)
        #expect(flow.canAdvance == true)
        flow.advance()
        #expect(flow.step == .model)
    }

    @Test("Model blocks until one is downloaded")
    func modelIsBlocking() {
        let requirements = FakeRequirements(mic: true, accessibility: true)
        let flow = OnboardingFlow(requirements: requirements)
        flow.advance()

        #expect(flow.step == .model)
        #expect(flow.canAdvance == false)
        flow.advance()
        #expect(flow.step == .model)

        requirements.hasUsableModel = true
        flow.advance()
        #expect(flow.step == .hotkey)
    }

    @Test("Everything already granted lands straight on the hotkey step")
    func satisfiedStepsAreSkipped() {
        let flow = OnboardingFlow(
            requirements: FakeRequirements(mic: true, accessibility: true, model: true)
        )
        flow.advance()
        #expect(flow.step == .hotkey)
    }

    @Test("Back walks the steps in reverse and stops at welcome")
    func backStopsAtWelcome() {
        let requirements = FakeRequirements(mic: true)
        let flow = OnboardingFlow(requirements: requirements)
        flow.advance()
        #expect(flow.step == .accessibility)

        flow.back()
        #expect(flow.step == .microphone)
        flow.back()
        #expect(flow.step == .welcome)
        flow.back()
        #expect(flow.step == .welcome)
    }

    @Test("Back does not re-skip a satisfied step, otherwise it would be a trap")
    func backIgnoresSatisfaction() {
        let flow = OnboardingFlow(
            requirements: FakeRequirements(mic: true, accessibility: true, model: true)
        )
        flow.advance()
        #expect(flow.step == .hotkey)

        flow.back()
        #expect(flow.step == .model)
    }

    @Test("Done is terminal")
    func doneIsTerminal() {
        let flow = OnboardingFlow(
            requirements: FakeRequirements(mic: true, accessibility: true, model: true)
        )
        flow.advance()
        flow.advance()
        #expect(flow.step == .done)
        #expect(flow.canAdvance == false)

        flow.advance()
        #expect(flow.step == .done)
    }
}
```

- [ ] **Step 2: Lancer les tests pour vérifier qu'ils échouent**

Run (avec `dangerouslyDisableSandbox: true`) :
```bash
xcodebuild -project Whispeur.xcodeproj -scheme WhispeurTests test -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData
```
Expected: échec de compilation — `cannot find type 'OnboardingRequirements' in scope`.

- [ ] **Step 3: Écrire la machine à états**

Créer `Whispeur/Models/OnboardingFlow.swift` :

```swift
// OnboardingFlow.swift
// Whispeur
//
// Step sequencing for the first-launch setup.
//
// No UI and no system call live here: what macOS actually grants comes in
// through the injected requirements, so the whole progression is testable
// without permissions, downloads or a window.

import Foundation

// MARK: - Steps

enum OnboardingStep: Int, CaseIterable, Comparable, Sendable {
    case welcome
    case microphone
    case accessibility
    case model
    case hotkey
    case done

    static func < (lhs: OnboardingStep, rhs: OnboardingStep) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Injected dependency

@MainActor
protocol OnboardingRequirements {
    var isMicrophoneGranted: Bool { get }
    var isAccessibilityGranted: Bool { get }
    var hasUsableModel: Bool { get }
}

// MARK: - Flow

@MainActor
@Observable
final class OnboardingFlow {

    private(set) var step: OnboardingStep = .welcome

    private let requirements: any OnboardingRequirements

    init(requirements: any OnboardingRequirements) {
        self.requirements = requirements
    }

    /// Microphone and model are blocking: without them Whispeur cannot dictate
    /// at all. Accessibility only degrades auto-paste to a clipboard copy, so
    /// refusing it must not trap the user on that page.
    var canAdvance: Bool {
        switch step {
        case .welcome, .accessibility, .hotkey: return true
        case .microphone: return requirements.isMicrophoneGranted
        case .model:      return requirements.hasUsableModel
        case .done:       return false
        }
    }

    func advance() {
        guard canAdvance, let next = OnboardingStep(rawValue: step.rawValue + 1) else { return }
        step = next
        skipSatisfiedSteps()
    }

    /// Deliberately does not skip: a reinstall would otherwise bounce the user
    /// straight back forward, making the Back button look broken.
    func back() {
        guard let previous = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    /// Someone reinstalling should not be walked through permissions they have
    /// already given.
    private func skipSatisfiedSteps() {
        while isSatisfied(step), let next = OnboardingStep(rawValue: step.rawValue + 1) {
            step = next
        }
    }

    private func isSatisfied(_ step: OnboardingStep) -> Bool {
        switch step {
        case .microphone:    return requirements.isMicrophoneGranted
        case .accessibility: return requirements.isAccessibilityGranted
        case .model:         return requirements.hasUsableModel
        case .welcome, .hotkey, .done: return false
        }
    }
}
```

- [ ] **Step 4: Régénérer le projet et lancer les tests**

Run (avec `dangerouslyDisableSandbox: true`) :
```bash
xcodegen generate && xcodebuild -project Whispeur.xcodeproj -scheme WhispeurTests test -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData
```
Expected: PASS — les 8 nouveaux tests plus tous les existants.

- [ ] **Step 5: Commit**

```bash
git add Whispeur/Models/OnboardingFlow.swift WhispeurTests/OnboardingFlowTests.swift Whispeur.xcodeproj
git commit -m "feat(onboarding): add step flow with injectable requirements"
```

---

### Task 3: Requirements réels et pages de l'onboarding

**Files:**
- Create: `Whispeur/Views/OnboardingView.swift`
- Modify: `Whispeur/Models/OnboardingFlow.swift` (ajout en fin de fichier)

**Interfaces:**
- Consumes: `OnboardingStep`, `OnboardingRequirements`, `OnboardingFlow` (Task 2) ; `MicrophonePermissionManager`, `ModelManager`, `AppSettings`, `RecordingCoordinator`, `ServicesContainer` (existants)
- Produces:
  - `@MainActor struct SystemOnboardingRequirements: OnboardingRequirements` — `init(micManager: MicrophonePermissionManager, settings: AppSettings)`
  - `struct OnboardingView: View` — `init(services: ServicesContainer, onFinish: @escaping () -> Void)`

- [ ] **Step 1: Écrire l'implémentation réelle des requirements**

Ajouter à la fin de `Whispeur/Models/OnboardingFlow.swift`. `import ApplicationServices` est nécessaire pour `AXIsProcessTrusted`.

Remplacer `import Foundation` en tête de fichier par :

```swift
import Foundation
import ApplicationServices
```

Puis, à la fin du fichier :

```swift
// MARK: - Real requirements

@MainActor
struct SystemOnboardingRequirements: OnboardingRequirements {
    let micManager: MicrophonePermissionManager
    let settings: AppSettings

    var isMicrophoneGranted: Bool { micManager.canRecord }

    var isAccessibilityGranted: Bool { AXIsProcessTrusted() }

    /// The selected model specifically — having *some* model on disk is not
    /// enough, the pipeline loads the selected one.
    var hasUsableModel: Bool { settings.selectedModelDescriptor?.isDownloaded ?? false }
}
```

- [ ] **Step 2: Ajouter les deux descripteurs nommés**

La vue du Step 3 référence `WhisperModelDescriptor.onboardingDefault` et `.onboardingLight`. Les ajouter dans `Whispeur/Models/WhisperModel.swift`, juste après `static var testModel` :

```swift
    /// Best quality-per-second of the catalog: turbo is only weaker at
    /// translation, which Whispeur never does (`params.translate = false`).
    static var onboardingDefault: WhisperModelDescriptor {
        catalog.first { $0.name == "large-v3-turbo-q5_0" }!
    }

    /// Offered as a way out on slow connections.
    static var onboardingLight: WhisperModelDescriptor {
        catalog.first { $0.name == "base-q5_1" }!
    }
```

- [ ] **Step 3: Écrire la vue**

Créer `Whispeur/Views/OnboardingView.swift`. La vue réutilise `SettingsCard` et `SectionHeader` de `SettingsComponents.swift`, et force `.preferredColorScheme(.dark)` comme la fenêtre de réglages.

```swift
// OnboardingView.swift
// Whispeur
//
// First-launch setup: one page per OnboardingFlow step.
// Accessibility trust is re-read on every appearance because the user grants it
// in System Settings, outside the app — nothing notifies us.

import SwiftUI
import AppKit
import ApplicationServices

struct OnboardingView: View {
    let services: ServicesContainer
    let onFinish: () -> Void

    @State private var flow: OnboardingFlow
    @State private var isAXTrusted = false

    init(services: ServicesContainer, onFinish: @escaping () -> Void) {
        self.services = services
        self.onFinish = onFinish
        _flow = State(
            initialValue: OnboardingFlow(
                requirements: SystemOnboardingRequirements(
                    micManager: services.micPermManager,
                    settings: services.settings
                )
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            page
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(28)

            Divider().opacity(0.12)

            footer
                .padding(16)
        }
        .frame(width: 520, height: 460)
        .preferredColorScheme(.dark)
        .onAppear { isAXTrusted = AXIsProcessTrusted() }
    }

    // MARK: - Pages

    @ViewBuilder
    private var page: some View {
        switch flow.step {
        case .welcome:       welcomePage
        case .microphone:    microphonePage
        case .accessibility: accessibilityPage
        case .model:         modelPage
        case .hotkey:        hotkeyPage
        case .done:          donePage
        }
    }

    private var welcomePage: some View {
        pageLayout(
            icon: "mic.fill",
            title: "Bienvenue dans Whispeur",
            subtitle: "Dictez dans n'importe quelle application. Votre voix est transcrite sur votre Mac, sans jamais partir sur Internet."
        ) {
            EmptyView()
        }
    }

    private var microphonePage: some View {
        pageLayout(
            icon: "waveform",
            title: "Accès au microphone",
            subtitle: "Whispeur a besoin du micro pour capturer votre voix. Sans cette autorisation, la dictée ne peut pas fonctionner."
        ) {
            VStack(spacing: 10) {
                if services.micPermManager.canRecord {
                    statusLine(granted: true, text: "Microphone autorisé")
                } else {
                    Button("Autoriser le microphone") {
                        Task { await services.micPermManager.requestIfNeeded() }
                    }
                    .buttonStyle(.borderedProminent)

                    if services.micPermManager.status == .denied {
                        Button("Ouvrir les Réglages Système") {
                            services.micPermManager.openSystemPreferences()
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.white.opacity(0.6))
                    }
                }
            }
        }
    }

    private var accessibilityPage: some View {
        pageLayout(
            icon: "hand.tap.fill",
            title: "Collage automatique",
            subtitle: "Avec l'autorisation d'Accessibilité, Whispeur colle le texte directement dans l'application active. Sans elle, le texte est copié dans le presse-papier — vous collez avec ⌘V."
        ) {
            VStack(spacing: 10) {
                if isAXTrusted {
                    statusLine(granted: true, text: "Accessibilité autorisée")
                } else {
                    Button("Ouvrir les Réglages Système") {
                        openAccessibilitySettings()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Vérifier à nouveau") {
                        isAXTrusted = AXIsProcessTrusted()
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
    }

    private var modelPage: some View {
        pageLayout(
            icon: "cube.box.fill",
            title: "Modèle de transcription",
            subtitle: "Le modèle tourne sur votre Mac. Le téléchargement n'a lieu qu'une fois."
        ) {
            VStack(spacing: 12) {
                modelRow(WhisperModelDescriptor.onboardingDefault, recommended: true)
                modelRow(WhisperModelDescriptor.onboardingLight, recommended: false)
            }
        }
    }

    private var hotkeyPage: some View {
        pageLayout(
            icon: "keyboard",
            title: "Essayez",
            subtitle: "Maintenez la touche 🎤 de votre clavier, dites une phrase, puis relâchez. Le texte apparaît ci-dessous."
        ) {
            VStack(spacing: 10) {
                Text(services.coordinator.lastTranscription.isEmpty
                     ? "En attente de votre première dictée…"
                     : services.coordinator.lastTranscription)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(services.coordinator.lastTranscription.isEmpty ? 0.3 : 0.85))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                    )
            }
        }
    }

    private var donePage: some View {
        pageLayout(
            icon: "checkmark.circle.fill",
            title: "Tout est prêt",
            subtitle: "Whispeur vit dans la barre de menus. Retrouvez-y vos modèles, votre historique et vos réglages."
        ) {
            EmptyView()
        }
    }

    // MARK: - Building blocks

    private func pageLayout<Content: View>(
        icon: String,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 14) {
            Spacer()

            Image(systemName: icon)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.white.opacity(0.75))

            Text(title)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))

            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 380)

            content()
                .padding(.top, 4)

            Spacer()
        }
    }

    private func statusLine(granted: Bool, text: LocalizedStringKey) -> some View {
        HStack(spacing: 6) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(granted ? Color.green : Color.white.opacity(0.3))
            Text(text)
                .foregroundStyle(.white.opacity(0.8))
        }
        .font(.system(size: 12, weight: .medium))
    }

    private func modelRow(_ model: WhisperModelDescriptor, recommended: Bool) -> some View {
        let state = ModelManager.shared.state(for: model)

        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(model.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                    if recommended {
                        Text("recommandé")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
                Text(model.sizeInfo)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.35))
            }

            Spacer()

            switch state {
            case .done:
                Button("Utiliser") { select(model) }
                    .buttonStyle(.borderedProminent)
            case .downloading(let progress):
                ProgressView(value: progress)
                    .frame(width: 90)
            case .installing:
                ProgressView().controlSize(.small)
            case .failed(let message):
                Text(message)
                    .font(.system(size: 10))
                    .foregroundStyle(.red.opacity(0.8))
            case .idle:
                Button("Télécharger") {
                    ModelManager.shared.download(model)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if flow.step != .welcome && flow.step != .done {
                Button("Retour") { flow.back() }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.white.opacity(0.5))
            }

            Spacer()

            if flow.step == .done {
                Button("Terminer") { onFinish() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Continuer") { flow.advance() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!flow.canAdvance)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: - Actions

    private func select(_ model: WhisperModelDescriptor) {
        services.settings.selectedModelFilename = model.filename
        services.coordinator.modelURL = model.localURL
    }

    private func openAccessibilitySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}
```

- [ ] **Step 4: Régénérer et compiler**

Run (avec `dangerouslyDisableSandbox: true`) :
```bash
xcodegen generate && xcodebuild -project Whispeur.xcodeproj -scheme Whispeur -configuration Debug build -derivedDataPath build/DerivedData
```
Expected: BUILD SUCCEEDED. Si le compilateur se plaint que `lastTranscription` est inaccessible, vérifier qu'il est bien `private(set) var` sur `RecordingCoordinator` (`Whispeur/Services/RecordingCoordinator.swift:42`) — la lecture depuis la vue est permise.

- [ ] **Step 5: Lancer les tests**

Run (avec `dangerouslyDisableSandbox: true`) :
```bash
xcodebuild -project Whispeur.xcodeproj -scheme WhispeurTests test -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData
```
Expected: PASS. `WhisperModel.swift` fait partie des sources de test, les deux nouveaux accesseurs doivent donc compiler — un `!` qui échouerait signifierait une faute de frappe dans le nom du modèle.

- [ ] **Step 6: Commit**

```bash
git add Whispeur/Models/OnboardingFlow.swift Whispeur/Models/WhisperModel.swift Whispeur/Views/OnboardingView.swift Whispeur.xcodeproj
git commit -m "feat(onboarding): add setup pages and system requirements"
```

---

### Task 4: Fenêtre et déclenchement au lancement

**Files:**
- Create: `Whispeur/Views/OnboardingWindowController.swift`
- Modify: `Whispeur/App/WhispeurApp.swift:62-90` (`applicationDidFinishLaunching`)

**Interfaces:**
- Consumes: `OnboardingView` (Task 3), `AppSettings.hasCompletedOnboarding` (Task 1)
- Produces: `@MainActor final class OnboardingWindowController` — `static let shared`, `func show(services: ServicesContainer)`

- [ ] **Step 1: Écrire le contrôleur de fenêtre**

Créer `Whispeur/Views/OnboardingWindowController.swift`, calqué sur `SettingsWindowController` :

```swift
// OnboardingWindowController.swift
// Whispeur
//
// Hosts the first-launch setup in its own window. LSUIElement apps have no
// window by default, so the app has to be activated explicitly or the window
// opens behind whatever the user was doing.

import SwiftUI
import AppKit

@MainActor
final class OnboardingWindowController: NSObject {
    static let shared = OnboardingWindowController()

    private var window: NSWindow?

    func show(services: ServicesContainer) {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = OnboardingView(services: services) { [weak self] in
            services.settings.hasCompletedOnboarding = true
            self?.close()
        }

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 460),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = String(localized: "Configuration de Whispeur")
        newWindow.center()
        newWindow.isReleasedWhenClosed = false
        newWindow.contentViewController = NSHostingController(rootView: view)

        window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func close() {
        window?.close()
        window = nil
    }
}
```

- [ ] **Step 2: Déclencher au premier lancement**

Dans `Whispeur/App/WhispeurApp.swift`, remplacer le bloc de demande de permission micro :

```swift
        // Microphone permission (non-blocking).
        Task { @MainActor in
            await sc.micPermManager.requestIfNeeded()
        }
```

par :

```swift
        // The onboarding asks for the microphone itself, with an explanation
        // shown first — prompting here would fire the system dialog cold.
        if sc.settings.hasCompletedOnboarding {
            Task { @MainActor in
                await sc.micPermManager.requestIfNeeded()
            }
        } else {
            OnboardingWindowController.shared.show(services: sc)
        }
```

- [ ] **Step 3: Régénérer et compiler**

Run (avec `dangerouslyDisableSandbox: true`) :
```bash
xcodegen generate && xcodebuild -project Whispeur.xcodeproj -scheme Whispeur -configuration Debug build -derivedDataPath build/DerivedData
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Vérifier le premier lancement en conditions réelles**

Effacer le flag et lancer l'app buildée :
```bash
defaults delete com.whispeur.Whispeur hasCompletedOnboarding 2>/dev/null
open build/DerivedData/Build/Products/Debug/Whispeur.app
```
Expected: la fenêtre d'onboarding s'ouvre au premier plan. La fermer via « Terminer », quitter l'app, la relancer : la fenêtre ne doit plus apparaître.

- [ ] **Step 5: Commit**

```bash
git add Whispeur/Views/OnboardingWindowController.swift Whispeur/App/WhispeurApp.swift Whispeur.xcodeproj
git commit -m "feat(onboarding): show setup window on first launch"
```

---

### Task 5: Traductions anglaises

**Files:**
- Modify: `Whispeur/Localizable.xcstrings`

**Interfaces:**
- Consumes: les chaînes UI des Tasks 3 et 4
- Produces: rien

- [ ] **Step 1: Ajouter les entrées**

`Localizable.xcstrings` est un JSON dont la langue source est le français. Le fichier contient 92 entrées avant cette tâche. « Télécharger » n'est volontairement pas dans la liste ci-dessous : elle est déjà traduite pour `ModelSection`, et la réassigner écraserait l'entrée existante.

```bash
jq --indent 2 '
  def entry(v): { "extractionState": "manual", "localizations": { "en": { "stringUnit": { "state": "translated", "value": v } } } };
  .strings["Configuration de Whispeur"] = entry("Set up Whispeur") |
  .strings["Bienvenue dans Whispeur"] = entry("Welcome to Whispeur") |
  .strings["Dictez dans n'\''importe quelle application. Votre voix est transcrite sur votre Mac, sans jamais partir sur Internet."] = entry("Dictate into any app. Your voice is transcribed on your Mac and never leaves it.") |
  .strings["Accès au microphone"] = entry("Microphone access") |
  .strings["Whispeur a besoin du micro pour capturer votre voix. Sans cette autorisation, la dictée ne peut pas fonctionner."] = entry("Whispeur needs the microphone to capture your voice. Without it, dictation cannot work.") |
  .strings["Autoriser le microphone"] = entry("Allow microphone") |
  .strings["Microphone autorisé"] = entry("Microphone allowed") |
  .strings["Ouvrir les Réglages Système"] = entry("Open System Settings") |
  .strings["Collage automatique"] = entry("Automatic pasting") |
  .strings["Avec l'\''autorisation d'\''Accessibilité, Whispeur colle le texte directement dans l'\''application active. Sans elle, le texte est copié dans le presse-papier — vous collez avec ⌘V."] = entry("With Accessibility access, Whispeur pastes text straight into the active app. Without it, text is copied to the clipboard — paste it with ⌘V.") |
  .strings["Accessibilité autorisée"] = entry("Accessibility allowed") |
  .strings["Vérifier à nouveau"] = entry("Check again") |
  .strings["Modèle de transcription"] = entry("Transcription model") |
  .strings["Le modèle tourne sur votre Mac. Le téléchargement n'\''a lieu qu'\''une fois."] = entry("The model runs on your Mac. It is downloaded only once.") |
  .strings["recommandé"] = entry("recommended") |
  .strings["Utiliser"] = entry("Use") |
  .strings["Essayez"] = entry("Try it") |
  .strings["Maintenez la touche 🎤 de votre clavier, dites une phrase, puis relâchez. Le texte apparaît ci-dessous."] = entry("Hold the 🎤 key on your keyboard, say a sentence, then release. The text appears below.") |
  .strings["En attente de votre première dictée…"] = entry("Waiting for your first dictation…") |
  .strings["Tout est prêt"] = entry("You are all set") |
  .strings["Whispeur vit dans la barre de menus. Retrouvez-y vos modèles, votre historique et vos réglages."] = entry("Whispeur lives in the menu bar. Your models, history and settings are all there.") |
  .strings["Retour"] = entry("Back") |
  .strings["Continuer"] = entry("Continue") |
  .strings["Terminer"] = entry("Finish")
' Whispeur/Localizable.xcstrings > "$TMPDIR/xcstrings.json" && mv "$TMPDIR/xcstrings.json" Whispeur/Localizable.xcstrings
```

- [ ] **Step 2: Vérifier le fichier**

```bash
jq '.strings | length' Whispeur/Localizable.xcstrings
```
Expected: `116`

- [ ] **Step 3: Compiler et lancer les tests**

Run (avec `dangerouslyDisableSandbox: true`) :
```bash
xcodebuild -project Whispeur.xcodeproj -scheme Whispeur -configuration Debug build -derivedDataPath build/DerivedData
xcodebuild -project Whispeur.xcodeproj -scheme WhispeurTests test -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData
```
Expected: BUILD SUCCEEDED puis PASS.

- [ ] **Step 4: Commit**

```bash
git add Whispeur/Localizable.xcstrings
git commit -m "chore(i18n): translate onboarding strings"
```

---

## Vérification manuelle finale

Les tests unitaires couvrent le séquencement, pas les dialogues système ni le téléchargement. Ces scénarios sont à passer à la main sur l'app buildée, une fois les 5 tâches terminées.

Pour repartir d'un état vierge entre deux essais :
```bash
defaults delete com.whispeur.Whispeur hasCompletedOnboarding
rm -rf ~/Library/Application\ Support/Whispeur/Models
```
Révoquer aussi le micro et l'Accessibilité dans Réglages Système › Confidentialité et sécurité.

1. **Parcours complet à froid** — micro refusé au départ : le bouton « Continuer » reste désactivé sur l'étape micro, et s'active dès l'autorisation accordée.
2. **Accessibilité refusée** — « Continuer » reste actif : l'étape est facultative. Aller jusqu'au bout, dicter : le texte atterrit dans le presse-papier avec une notification.
3. **Téléchargement du modèle** — la progression avance, puis « Continuer » se débloque. Couper le Wi-Fi en cours de téléchargement : l'erreur s'affiche dans la ligne du modèle sans bloquer la fenêtre.
4. **Dictée d'essai** — sur l'étape « Essayez », maintenir 🎤 et parler : le texte transcrit apparaît dans le cadre.
5. **Deuxième lancement** — l'onboarding ne réapparaît pas.
6. **Réinstallation simulée** — remettre `hasCompletedOnboarding` à `false` en gardant micro, Accessibilité et modèle en place : « Continuer » depuis l'écran d'accueil doit sauter directement à l'étape « Essayez ».
