#!/usr/bin/env bash
# dump.sh — snapshot current machine state into manifests/.
# Run weekly via launchd (macOS). No auto-commit; review and commit by hand.
set -euo pipefail

cd "$(chezmoi source-path)"

echo "=== dumping machine state ==="

# Homebrew
if command -v brew >/dev/null 2>&1; then
    echo "  brew bundle dump..."
    brew bundle dump --force --file manifests/Brewfile
fi

# Fisher plugins
if command -v fish >/dev/null 2>&1; then
    echo "  fisher list..."
    fish -c 'fisher list' > manifests/fisher.txt 2>/dev/null || true
fi

# pipx packages
if command -v pipx >/dev/null 2>&1; then
    echo "  pipx list..."
    pipx list --short > manifests/pipx.txt 2>/dev/null || true
fi

echo ""
git diff --stat
echo ""
echo "review, curate, commit by hand."
