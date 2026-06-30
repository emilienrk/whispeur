# Compte Rendu des Besoins : Application de Dictée Vocale (Wrapper whisper.cpp)

Ce document répertorie le cahier des charges de l'application. Il est divisé en deux parties : les éléments strictement imposés par le besoin de l'utilisateur, et les choix techniques laissés à l'appréciation de l'IA lors du développement.

---

## PARTIE 1 : ÉLÉMENTS IMPOSÉS

### 1. Vision Globale
- Créer une application minimaliste, ultra-rapide, très légère et hautement optimisée pour macOS.
- **Objectif :** Accélérer la saisie de texte grâce à la voix, assistée par l'IA, en utilisant `whisper.cpp` comme moteur de transcription local.
- **Développement :** Le projet sera codé à 100% par des IA (notamment Claude / Claude Code).

### 2. Fonctionnalités et Comportement
- **Déclenchement de la dictée :** Via un raccourci clavier global.
- **Actions post-transcription :**
  - Copier le texte transcrit directement dans le presse-papier macOS.
  - OU coller automatiquement le texte à l'emplacement actif du curseur (en cas d'édition de texte).
- **Moteur de transcription (`whisper.cpp`) :**
  - L'application est un *wrapper* autour du projet `whisper.cpp`.
  - **Contrainte absolue :** Le code source du moteur `whisper.cpp` ne doit **absolument pas** être modifié. L'application doit permettre de récupérer facilement les dernières mises à jour du moteur via de simples commandes `git pull` sur le dépôt officiel.
- **Exécution en arrière-plan :** L'application doit pouvoir tourner silencieusement en tâche de fond pour écouter les raccourcis, sans avoir besoin d'afficher une icône permanente dans le Dock.
- **Gestion des cas d'erreur ("ratés") :** Si le raccourci est utilisé mais qu'aucun champ de texte n'est actif, l'application doit émettre une simple notification macOS pour informer l'utilisateur de l'échec du collage.

### 3. Interface Utilisateur (UI / UX) et Paramètres
L'application doit disposer d'une interface de "Paramètres" (Settings), qui peut être affichée à la demande de l'utilisateur. Cette interface doit inclure :
- **Configuration du raccourci :** Choix des touches et définition du comportement (Mode "Push-to-Talk" / maintenir pour parler, ou mode "Bascule" / appuyer pour démarrer puis réappuyer pour arrêter).
- **Gestion des Modèles :** Sélection et téléchargement des différents modèles Whisper directement depuis l'interface. La liste des modèles et les fonctionnalités associées ne doivent pas être statiques : elles doivent s'adapter dynamiquement si le moteur `whisper.cpp` est mis à jour.
- **Gestion de la Langue :** Un paramètre permettant de choisir entre une détection automatique de la langue ("Auto") ou de forcer une langue précise.
- **Gestion des Autorisations macOS :** L'interface doit guider l'utilisateur pour l'activation des permissions de sécurité macOS nécessaires au bon fonctionnement (Accès au Microphone, et Accès aux options d'Accessibilité pour la simulation de frappe clavier).

### 4. Contraintes d'Infrastructure
- **Accélération Matérielle :** L'application et surtout le moteur `whisper.cpp` doivent **impérativement** être compilés pour utiliser l'accélération matérielle d'Apple Silicon (support Metal / GPU ou Neural Engine) afin de garantir une transcription instantanée.
- **Choix Technologique :** La stack doit offrir le meilleur équilibre entre :
  1. Une optimisation extrême pour macOS (très léger, le plus natif possible).
  2. Une forte maîtrise et une excellente documentation par l'IA (afin de garantir un code généré fiable et limiter les bugs).

---

## PARTIE 2 : ÉLÉMENTS À DÉFINIR PAR L'IA

Pour réaliser ce projet en respectant les éléments imposés ci-dessus, les choix d'architecture suivants sont **à définir par l'IA** lors de la phase de conception technique :

1. **Choix de la Stack Technique [À DÉFINIR] :**
   - L'IA devra choisir la technologie la plus pertinente (ex: SwiftUI pour le 100% natif/léger macOS, ou Tauri pour la légèreté couplée à des technos web maîtrisées, ou autre solution optimale).
2. **Communication avec `whisper.cpp` [À DÉFINIR] :**
   - L'IA devra déterminer la meilleure méthode de communication entre l'application et le moteur (Appels en ligne de commande / sous-processus CLI, utilisation de l'exécutable compilé, ou intégration directe via `libwhisper`).
3. **Gestion de la Capture Audio [À DÉFINIR] :**
   - L'IA devra évaluer la méthode la plus efficace pour l'enregistrement audio : est-il préférable d'utiliser l'exécutable natif de test de `whisper.cpp` (comme l'outil `stream`) pour capturer la voix, ou le wrapper doit-il gérer lui-même la capture du micro via les API macOS avant d'envoyer l'audio au moteur ?
4. **Stratégie de Mise à jour du Moteur [À DÉFINIR] :**
   - L'IA devra définir l'arborescence exacte et la méthode permettant de garantir que les `git pull` sur le sous-dossier `whisper.cpp` ne créeront aucun conflit avec l'application wrapper.

---
*Note: Le cahier des charges actuel est très complet. Les seules informations manquantes concerneraient éventuellement le format de distribution souhaité à la fin (ex: fichier .app ou .dmg), mais cela fait partie des standards de compilation de la stack technique qui sera définie par l'IA.*
