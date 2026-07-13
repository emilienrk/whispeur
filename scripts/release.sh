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
