# 🧠 Guide d'Intégration whisper.cpp (Pour l'IA Développeuse)

> [!IMPORTANT]
> **À l'attention de l'IA qui écrira le code :** Ce document contient le condensé de l'analyse architecturale du moteur `whisper.cpp`. Il t'évitera de fouiller dans les milliers de lignes de C++ et te donne les contraintes exactes pour l'intégration macOS (Apple Silicon). **Lis-le attentivement.**

## 1. Fichiers Sources de Référence
L'implémentation de Whispeur doit s'inspirer STRICTEMENT de ces fichiers officiels présents dans le submodule `whisper.cpp` :

*   **Le Bridging Swift / C++ :** `whisper.cpp/examples/whisper.swiftui/whisper.cpp.swift/LibWhisper.swift`
    *   *Sujet :* Comment instancier le `WhisperContext` de façon thread-safe (`actor` Swift), comment activer Metal (`params.use_gpu = true`), et comment extraire le texte.
*   **Le Flux Audio & Orchestration :** `whisper.cpp/examples/whisper.swiftui/whisper.swiftui.demo/Models/WhisperState.swift`
    *   *Sujet :* La gestion de l'état global. **Attention :** Ne copie pas leur logique d'enregistrement (`AVAudioRecorder`), utilise `AVAudioEngine` à la place (voir point 3).
*   **Les Constantes & Options :** `whisper.cpp/include/whisper.h`
    *   *Sujet :* C'est l'API C officielle. Cherche ici si tu as besoin de configurer l'auto-détection de langue, les threads, ou le VAD (Voice Activity Detection).

## 2. Compilation et Accélération Matérielle (Metal vs CoreML)
Le projet doit tourner à la vitesse de l'éclair sur macOS Apple Silicon.

### Le choix principal : **Metal (GPU)**
C'est le choix retenu pour Whispeur. La compilation via CMake (le script custom de build) doit inclure :
```bash
-DGGML_METAL=ON
-DGGML_METAL_EMBED_LIBRARY=ON
-DGGML_METAL_USE_BF16=ON
```
*Conséquence dans le code Swift :* L'accélération s'active simplement en passant `params.use_gpu = true` et `params.flash_attn = true` au moment d'appeler `whisper_full_default_params`.

### L'alternative ignorée : **CoreML (Neural Engine)**
`whisper.cpp` supporte CoreML (`WHISPER_COREML=ON`), mais **nous l'écartons pour la v1**.
*Pourquoi ?* Cela obligerait l'utilisateur à télécharger des modèles Whisper pré-compilés au format `.mlmodelc` (ou à exécuter des scripts Python locaux), ce qui casse la promesse d'une app simple et autonome. Metal est amplement suffisant (temps de réponse < 500ms). N'essaie pas d'intégrer CoreML.

## 3. Le Piège de l'Audio (Crucial)
`whisper.cpp` est extrêmement strict sur le format audio.
*   **Format exigé :** PCM Linéaire, **16000 Hz**, **Mono** (1 canal), tableaux de `Float` (Float32).

**L'erreur classique (présente dans la démo officielle) :**
La démo officielle SwiftUI utilise `AVAudioRecorder` pour écrire un `.wav` sur le disque dur, puis le relit et le convertit en Float. **Interdiction de faire ça.** Cela tue les performances et use le SSD.

**La solution imposée pour Whispeur :**
Utilise `AVAudioEngine`.
1.  Connecte un *tap* sur `audioEngine.inputNode`.
2.  Le format du tap DOIT être explicitement converti si le micro natif n'est pas en 16kHz (utilise `AVAudioConverter` ou downsample manuellement depuis le `AVAudioPCMBuffer`).
3.  Stocke les samples `Float` directement dans un buffer en RAM (`[Float]`).
4.  À la fin de la dictée, passe le tableau `[Float]` directement à `whisper_full()`. Zéro I/O disque.

## 4. Gestion de la Mémoire et Thread Safety
*   L'API C de Whisper **n'est pas thread-safe** pour un même contexte.
*   Le modèle Whisper (`WhisperContext`) pèse lourd en RAM (150MB à 1.5GB selon le modèle). Il ne doit être initialisé qu'**une seule fois** au lancement ou lors du changement de modèle.
*   Encapsule le pointeur Opaque C dans un **`actor` Swift** (comme dans `LibWhisper.swift`) pour garantir l'accès séquentiel exclusif et éviter les crashs de concurrence.
*   Assure-toi d'appeler `whisper_free()` dans le `deinit` de l'actor pour éviter les fuites de mémoire.

## 5. Le Catalogue de Modèles
Ne perds pas de temps à chercher les URLs de téléchargement des modèles HuggingFace. Elles sont toutes listées dans le fichier de l'exemple :
`whisper.cpp/examples/whisper.swiftui/whisper.swiftui.demo/UI/ContentView.swift` (Lignes 85 à 119).
Copie/colle cette structure de données pour alimenter ton `ModelManager`. Les variantes recommandées pour Whispeur sont `base` (rapide et précis) et `base.en` (si anglais uniquement).

## 6. Accessibilité (Simulation de Clavier)
Pour coller le texte via le mode "automatique", l'app a besoin des droits Accessibility.
*   Utilise `CGEvent(keyboardEventSource:virtualKey:keyDown:)` pour simuler `Cmd+V`.
*   N'oublie pas que l'utilisateur devra autoriser l'app dans Préférences Système > Confidentialité. Prépare une UI élégante pour vérifier cet état (`AXIsProcessTrusted()`) sans bloquer brutalement l'app.
