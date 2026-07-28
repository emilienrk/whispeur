# Design : pause média décidée par processus

**Date :** 2026-07-29
**Statut :** validé
**Remplace :** `2026-07-24-pause-media-pendant-dictee-design.md`

## Ce qui n'allait pas

La première version interrogeait le périphérique de sortie par défaut via
`kAudioDevicePropertyDeviceIsRunningSomewhere`. Cette propriété répond « du son
sort-il, oui ou non » — elle ne dit pas *qui* le produit. Deux régressions en
découlaient, toutes deux observées :

1. **Dictée pendant un FaceTime.** L'appel faisait sortir du son, la sonde
   répondait « ça joue », la touche Play/Pause partait. macOS la route vers
   l'app *now playing* du système — un Spotify en pause — qui **démarrait**.
2. **Dictée suivante, sans appel.** La reprise de la dictée précédente avait
   laissé une dette. Elle s'est soldée au tour d'après : le silence attendu a
   été trouvé, `Play` a été envoyé, la musique a démarré alors que rien ne
   jouait.

Une seule cause : l'impossibilité d'attribuer le son à une application.

## Mécanisme retenu

`kAudioHardwarePropertyProcessObjectList`, avec pour chaque processus
`kAudioProcessPropertyBundleID`, `kAudioProcessPropertyPID`,
`kAudioProcessPropertyIsRunningOutput` et `kAudioProcessPropertyIsRunningInput`.

API **publique** depuis macOS 14.4, présente dans le SDK macOS 26, **sans
entitlement ni invite TCC** — seul `AudioHardwareCreateProcessTap`, qui capture
réellement les échantillons, en exigerait une, et Whispeur ne l'utilise pas.

Vérifié sur la machine de développement : Spotify ouvert mais en pause rapporte
`isRunningOutput = 0`. C'est exactement le cas que la sonde par périphérique ne
pouvait pas voir.

Notre propre PID est exclu des relevés. C'est ce qui rend une lecture valide
**micro ouvert**, et qui supprime la raison d'être de toute la machinerie de la
version précédente (sondage 50 ms, timeout 1 s, compteur de génération, dette
reportée) : elle n'existait que parce que sur un appareil d'entrée/sortie
partagé — les AirPods — notre propre capture faisait compter le périphérique
comme actif.

## Classer une source

`classify(_ process: AudioProcess) -> AudioSourceKind`, fonction pure.

Le signal principal est **comportemental** : un processus qui joue *et* capture
en même temps tient une conversation, il ne lit pas de la musique. Ça couvre les
apps qu'aucune liste ne pourrait nommer, dont un Google Meet dans un onglet —
il partage son processus avec YouTube, donc aucun bundle ID ne peut les
distinguer.

Une liste de bundle IDs sert de filet pour le cas que le signal comportemental
rate : Apple fait transiter l'audio FaceTime par des daemons, et celui qui joue
le correspondant n'est pas forcément celui qui tient le micro.
`com.apple.FaceTime`, `com.hnc.Discord` et `com.microsoft.teams2` ont été lus
sur les bundles installés ; `com.apple.avconferenced` et
`com.apple.TelephonyUtilities` ont été observés dans la liste des processus
audio. Les autres sont les identifiants publiés, non relus sur un bundle.

Sur-approximer est sans risque : classer un lecteur en `.communication` ne fait
jamais qu'abstenir Whispeur, jamais agir de travers.

## Algorithme

**Pause**, en tête de `startPipeline()` :

1. Réglage désactivé, ou une pause déjà due → rien.
2. Un processus `.communication` sort du son → **rien du tout**, musique
   comprise. Interrompre une conversation coûte plus cher que laisser un
   morceau tourner quelques secondes.
3. Aucun processus ne sort de son → **rien**. Un lecteur en pause est
   invisible, donc jamais réveillé.
4. Sinon → mémoriser les PID, envoyer la touche, poser la dette. La méthode
   rend la main immédiatement : rien n'est ajouté au délai d'ouverture du micro.

**Vérification**, dans une `Task`, après 400 ms : si un processus qui ne jouait
**pas** avant joue maintenant, la touche a réveillé un lecteur en pause au lieu
d'en arrêter un — on rebascule pour annuler et on abandonne la dette.

400 ms est mesuré, pas choisi : le drapeau met 74 à 84 ms à monter sur ce
matériel (5 essais), et cette mesure inclut le `fork`/`exec` du processus de
test, qu'une app déjà lancée n'a pas à payer.

**Reprise**, depuis `finishRecording()` et `setError()` : attendre le verdict de
la vérification, puis envoyer `Play` si la dette tient.

La reprise n'est **pas** conditionnée à la preuve que le lecteur s'est tu. Les
lecteurs gardent leur unité audio vivante plusieurs secondes après une pause —
Spotify le fait — donc exiger cette preuve laisserait la musique coupée. C'est
l'erreur de conception de la version précédente.

### Le mode de défaillance a changé de sens

Avant, dans le doute, Whispeur **démarrait** un lecteur. Maintenant, dans le
doute, il **laisse en pause**. Le pire cas devient « la musique reste coupée,
une touche pour la relancer » au lieu de « une musique démarre en pleine
visio ».

### Comportement par situation

| Situation | Pause | Reprise |
|---|---|---|
| Rien ne joue, lecteur ouvert mais en pause | aucune touche | aucune touche |
| Musique / vidéo seule | pause | play |
| Appel seul | aucune touche | aucune touche |
| Appel **et** musique | aucune touche | aucune touche |
| Navigateur, onglet ambigu, touche mal routée | pause puis annulation | aucune touche |

### Limites assumées

**Un son transitoire pendant la fenêtre de vérification** — une notification qui
démarre dans les 400 ms — se présente comme un démarrage intempestif et fait
annuler la pause. La musique n'est alors pas mise en pause pour cette dictée.
Bénin, et préférable au cas inverse.

**La liste de bundle IDs est une heuristique.** Une app de visio absente de la
liste et qui ne capture pas au moment du relevé serait traitée comme un lecteur.
La vérification limite les dégâts sans rendre la liste inutile.

## Composants

| Fichier | Rôle |
|---|---|
| `Whispeur/Services/AudioProcessProbe.swift` | **nouveau** — `AudioProcess`, protocole `AudioProcessProbe`, `classify`, et `CoreAudioProcessProbe` |
| `Whispeur/Services/MediaPlaybackController.swift` | réécrit — la politique seule, plus de plomberie CoreAudio |
| `Whispeur/Services/RecordingCoordinator.swift` | commentaires : la justification « avant l'ouverture du micro » est caduque |
| `Whispeur/App/WhispeurApp.swift` | `CoreAudioProcessProbe()` à l'injection |
| `project.yml` | le nouveau fichier ajouté aux sources de la cible de test |

`AppSettings` et `GeneralSection` ne changent pas : le réglage reste identique.

## Tests

`WhispeurTests/MediaPlaybackControllerTests.swift`, sonde simulée :
classification (capture simultanée, bundle listé, lecteur nu, bundle nil) ; rien
ne joue ; appel seul ; appel plus musique ; musique ; lecteur dont la sortie
s'attarde après la pause ; démarrage intempestif annulé ; réglage désactivé ;
reprise idempotente ; reprise sans pause ; dette en cours.

## Notes de build

Fichier ajouté → `xcodegen` avant de compiler, et penser aux sources de la
cible de test, qui sont listées une par une dans `project.yml`.
