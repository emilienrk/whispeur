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
