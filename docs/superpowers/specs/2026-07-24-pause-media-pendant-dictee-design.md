# Design : pause/reprise automatique de la musique pendant la dictée

**Date :** 2026-07-24
**Statut :** validé

## Objectif

Quand une dictée démarre, mettre en pause ce qui joue (Spotify, Apple Music,
YouTube dans le navigateur, VLC…) puis le relancer dès la fin de
l'enregistrement. Réglage activable/désactivable dans les préférences, activé
par défaut.

## Contexte technique

- Whispeur n'est **pas sandboxé** (`Whispeur.entitlements` ne contient que
  `device.audio-input` et `cs.disable-library-validation`).
- L'app pose déjà des `CGEvent` (collage via `ClipboardService`, event tap du
  `HotkeyManager`) : la permission **Accessibilité** est donc déjà accordée.
  Envoyer une touche média ne demande **aucune permission supplémentaire**.
- `MediaRemote` (le framework privé qui exposait le *now playing*) est
  verrouillé aux apps signées par Apple depuis macOS 15.4 — inutilisable ici.
  Le déploiement cible macOS 26.
- Les réglages suivent le pattern `AppSettings` (@Observable + `didSet` vers
  `UserDefaults`).
- `RecordingCoordinator` orchestre le pipeline et reçoit ses services par
  injection depuis `WhispeurApp`.

## Mécanisme retenu

**Touche média + sonde CoreAudio.** Deux primitives :

- **Détection** : `kAudioDevicePropertyDeviceIsRunningSomewhere` sur
  l'appareil de sortie par défaut → « du son sort-il, oui ou non ».
- **Contrôle** : `NX_KEYTYPE_PLAY` (16) posté en `NSEvent.systemDefined`
  sous-type 8 sur `.cghidEventTap`.

Alternatives écartées :

- **AppleScript ciblé (Spotify, Music)** : fiable sur ces apps mais ne couvre
  ni le navigateur ni VLC, et impose `NSAppleEventsUsageDescription` plus une
  autorisation TCC par application.
- **Hybride AppleScript + touche média** : couverture maximale au prix de deux
  chemins à maintenir et de la permission Apple Events. Écarté par YAGNI.

## Algorithme

La touche Play/Pause est une bascule aveugle : rien ne garantit qu'un lecteur
l'a reçue. La règle est donc de **n'envoyer Play que si l'on a la preuve que le
son s'est effectivement arrêté**, sans quoi une visio Zoom se terminerait par
Spotify démarrant tout seul.

**Pause — au début de `startPipeline()`, avant d'ouvrir le micro :**

1. Réglage désactivé → ne rien faire.
2. La sonde dit « rien ne sort » → `didPause = false`, ne rien faire.
3. Sinon → envoyer Play/Pause, `didPause = true`. L'enregistrement démarre
   immédiatement derrière, sans délai ajouté.

**Reprise — depuis `finishRecording()` et `setError()`, en parallèle de la
transcription :**

1. `didPause == false` → ne rien faire.
2. Remettre `didPause = false` immédiatement (idempotence), poser
   `resumePending = true`.
3. Sonder la sortie par intervalles de `resumePollInterval` (50 ms) jusqu'à
   `resumeTimeout` (1 s) après la fermeture du micro.
4. Dès qu'une lecture dit « plus rien ne sort » → envoyer Play/Pause, arrêter le
   sondage.
5. Le délai expire toujours bruyant → personne n'avait obéi, ou une autre
   source parle → **n'envoyer aucune touche**, et **garder la dette**
   (`didPause` repasse à `true`) pour que la prochaine dictée sache que le
   média est déjà en pause de son fait.

Une seule lecture à échéance fixe s'est révélée être un pari : fermer le micro
peut faire redémarrer un appareil d'entrée/sortie partagé (les AirPods changent
de profil Bluetooth HFP → A2DP au relâchement du micro), et
`kAudioDevicePropertyDeviceIsRunningSomewhere` reste vrai bien après une
fenêtre de 120 ms — la musique ne repartait jamais sur le matériel même que ce
document cite en exemple. Le sondage borné laisse à l'appareil le temps de se
stabiliser sans pour autant attendre indéfiniment.

### Pourquoi la vérification se fait à la reprise et non pendant

Une re-vérification pendant l'enregistrement serait fausse dès que l'entrée et
la sortie sont le même appareil (AirPods, casque USB, appareil agrégé) :
CoreAudio les expose comme un seul objet, et le micro ouvert par Whispeur suffit
à le faire compter comme « en train de tourner ». La musique ne repartirait
jamais.

En plaçant les lectures CoreAudio aux moments où le micro est fermé — avant
l'ouverture, et par sondages après la fermeture — aucune mesure n'est polluée
par notre propre capture. Même garantie anti-Zoom, sans cas particulier.

### La dette de reprise

`didPause` n'est pas qu'un drapeau d'idempotence : c'est une dette. Tant
qu'elle est due (parce qu'une reprise a expiré sans preuve de silence, ou
qu'une reprise est encore en train de sonder), le média est considéré comme
« en pause par nous », et une nouvelle dictée ne doit **jamais** rebasculer la
touche à l'aveugle — elle démarrerait un lecteur que Whispeur venait tout juste
de mettre en pause. `pauseForRecording()` vérifie donc `resumePending ||
didPause` **avant** de regarder si le réglage est actif : une dette se solde
même si l'utilisateur désactive le réglage entre deux dictées.

### Comportement par situation

La touche Play/Pause n'est **jamais ignorée** par macOS : elle est routée vers
l'app *now playing* du système (celle que Control Center désignerait). Si
cette app est en pause au moment où la touche arrive, elle **démarre** — c'est
la source du cas résiduel ci-dessous.

| Situation | Pause | Reprise |
|---|---|---|
| Rien ne joue | aucune touche | aucune touche |
| Spotify / YouTube / VLC | pause | play |
| Appel Zoom / Teams seul, aucune app *now playing* en pause | touche routée vers l'app now-playing, sans effet audible | aucune touche |
| Musique **et** Zoom | musique mise en pause | aucune touche — la musique reste coupée |

Le dernier cas est un compromis assumé : aucune API publique ne permet de
savoir *quelle* application produit du son. Le mode de défaillance choisi est
de ne jamais démarrer un lecteur que l'utilisateur n'a pas lancé.

#### Limite résiduelle assumée

Si un lecteur est ouvert **et en pause** (donc silencieux, la sonde ne le voit
pas) au moment où une dictée démarre pendant un appel visio, la touche
Play/Pause — routée vers cette app puisqu'elle est la *now playing* du
système — la **démarre**. Whispeur ne peut pas distinguer « aucune app now
playing » de « une app now playing en pause » avant d'envoyer la touche : les
deux se présentent comme un silence côté sonde CoreAudio.

Une fois le lecteur démarré par erreur, **Whispeur n'y retouche plus** : la
dette de reprise est due, donc `pauseForRecording()` sort par sa garde avant
d'envoyer quoi que ce soit, et la reprise ne trouve jamais le silence qu'elle
exige. Le lecteur joue donc jusqu'à la fin de l'appel, et l'utilisateur doit
l'arrêter lui-même.

C'est délibéré. Une fois la dette due, deux situations se présentent de façon
strictement identique au contrôleur — « musique correctement mise en pause,
plus le bruit de l'appel » et « lecteur démarré par erreur, plus le bruit de
l'appel » : dans les deux cas la dette est due et la sonde entend du son.
Rebasculer la touche corrigerait la seconde mais casserait la première en
redémarrant une musique que l'utilisateur voulait silencieuse. La garde protège
le cas correct, au prix du cas déjà dégradé.

Ce compromis a été examiné et validé par le porteur du projet — aucune API
publique ne permet de lever l'ambiguïté avant d'agir.

## Composants

### `Whispeur/Services/MediaPlaybackController.swift` (nouveau)

Deux dépendances derrière protocole, pour que la logique se teste sans son ni
matériel :

```swift
protocol SystemAudioProbe { var isOutputActive: Bool { get } }
protocol MediaKeySender   { func sendPlayPause() }
```

- `CoreAudioOutputProbe` : implémentation réelle de la sonde. Résout
  `kAudioHardwarePropertyDefaultOutputDevice` puis lit
  `kAudioDevicePropertyDeviceIsRunningSomewhere`. Toute erreur CoreAudio est
  traitée comme « rien ne sort » (mode sûr : on s'abstient).
- `SystemMediaKeySender` : implémentation réelle de l'émetteur. Poste la paire
  d'événements down/up.
- `MediaPlaybackController` : `@MainActor`, porte le seul état mutable
  `didPause: Bool`, expose `pauseForRecording()` et
  `resumeAfterRecording() async`.

Le contrôleur lit `AppSettings.shared.pauseMediaWhileRecording` au moment de la
pause uniquement. Une désactivation du réglage en cours d'enregistrement ne doit
pas laisser la musique coupée : la reprise ne dépend que de `didPause`.

### `Whispeur/Models/AppSettings.swift`

`pauseMediaWhileRecording: Bool`, clé UserDefaults `"pauseMediaWhileRecording"`,
défaut `true` — donc actif aussi pour les installations existantes après mise à
jour.

### `Whispeur/Services/RecordingCoordinator.swift`

Le contrôleur est injecté comme les autres services. `pauseForRecording()` est
appelé en tête de `startPipeline()`, **avant** `audioCapture.startRecording()`.
La reprise est déclenchée depuis `finishRecording()` et depuis `setError()` :
le guard `didPause` rend ces appels multiples inoffensifs et garantit que la
musique repart même si le modèle échoue à charger, si le micro refuse de
s'ouvrir ou si la transcription échoue.

### `Whispeur/Views/GeneralSection.swift`

`SettingsToggleRow` dans la carte « Comportement », sous « Son de
confirmation », icône `pause.circle.fill`. Label et description ajoutés à
`Whispeur/Localizable.xcstrings` en fr et en.

### `Whispeur/App/WhispeurApp.swift`

Construction du `MediaPlaybackController` avec ses implémentations réelles et
passage au `RecordingCoordinator`.

## Tests

`WhispeurTests/MediaPlaybackControllerTests.swift` (nouveau), avec une sonde et
un émetteur simulés :

- rien ne joue → 0 touche envoyée
- ça joue, silence à la reprise → 2 touches (pause puis play)
- ça joue, ça joue toujours à la reprise → 1 touche (cas Zoom), et la dette
  (`didPause`) est conservée
- une dette de reprise en cours empêche la dictée suivante de rebasculer la
  touche à l'aveugle
- réglage désactivé → 0 touche
- `resumeAfterRecording()` appelé deux fois → 1 seule touche
- `resumeAfterRecording()` sans pause préalable → 0 touche
- une dictée qui démarre pendant le sondage d'une reprise garde le média en
  pause et rend muette la reprise devenue obsolète

`PipelineStateTests` est ajusté si la nouvelle injection casse la construction
du coordinator.

## Notes de build

L'ajout de fichiers sources impose de relancer `xcodegen` avant de compiler
(voir le workflow de build du projet).
