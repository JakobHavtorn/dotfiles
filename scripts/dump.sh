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

# Fisher plugins — replaced by OMF (Oh My Fish) on this machine
# OMF packages are hand-curated in manifests/omf.txt (omf list output is not machine-parseable)

# pipx packages
if command -v pipx >/dev/null 2>&1; then
    echo "  pipx list..."
    pipx list --short | awk '{print $1}' > manifests/pipx.txt 2>/dev/null || true
fi

echo ""
git diff --stat
echo ""
echo "review, curate, commit by hand."
