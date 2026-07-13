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
