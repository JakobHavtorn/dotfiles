#!/usr/bin/env bash
# seed-github-ssh.sh — seed GitHub SSH auth on a fresh machine.
#
# The dotfiles repo is public, so this script can run before anything else
# exists on the box:
#
#   bash <(curl -fsLS https://raw.githubusercontent.com/JakobHavtorn/dotfiles/main/scripts/seed-github-ssh.sh)
#
# It stays self-contained (sources nothing from the repo) so it also works
# when transferred by hand — AirDrop, USB, or paste.
#
# Steps:
#   1. Generate an ed25519 key at ~/.ssh/id_github (the path the repo's SSH
#      config expects) unless one already exists.
#   2. Seed ~/.ssh/config.d/github and the `Include config.d/*` line in
#      ~/.ssh/config — byte-matching what chezmoi manages, so the first
#      apply converges with no diff.
#   3. Copy the public key to the clipboard and open
#      github.com/settings/keys in the browser. Adding the key on GitHub
#      is manual — the script waits for confirmation here.
#   4. Verify with `ssh -T git@github.com`.
#
# Exits 0 when GitHub accepts the key, 1 otherwise. Idempotent.
set -euo pipefail

: "${USER:=$(id -un)}"

KEY="$HOME/.ssh/id_github"
PUB="${KEY}.pub"
HOST_BLOCK="$HOME/.ssh/config.d/github"
GITHUB_URL="https://github.com/settings/keys"

mkdir -p "$HOME/.ssh" "$HOME/.ssh/config.d"

if [ -f "$KEY" ]; then
    echo "  key exists: $KEY — skipping keygen"
else
    echo "  generating ed25519 key at $KEY..."
    ssh-keygen -t ed25519 -C "$USER@$(hostname -s)" -f "$KEY"
fi

echo "  seeding $HOST_BLOCK..."
{
    echo "Host github.com"
    echo "  AddKeysToAgent yes"
    echo "  IdentityFile ~/.ssh/id_github"
    if [ "$(uname)" = "Darwin" ]; then
        echo "  UseKeychain yes"
    fi
} > "$HOST_BLOCK"

# Prepend the Include line if missing (same behavior as
# run_once_after_05-ssh-config.sh.tmpl).
if [ ! -f "$HOME/.ssh/config" ] || ! grep -qx 'Include config.d/\*' "$HOME/.ssh/config"; then
    echo "  adding 'Include config.d/*' to ~/.ssh/config..."
    {
        echo 'Include config.d/*'
        if [ -f "$HOME/.ssh/config" ]; then
            cat "$HOME/.ssh/config"
        fi
    } > "${HOME}/.ssh/config.tmp"
    mv "${HOME}/.ssh/config.tmp" "$HOME/.ssh/config"
fi

# Hand the public key to the user and open the browser. Adding the key on
# GitHub is the one manual step; the script blocks until the user confirms.
if [ "$(uname)" = "Darwin" ]; then
    if pbcopy < "$PUB" 2>/dev/null; then
        echo "  public key copied to clipboard"
    fi
    open "$GITHUB_URL" 2>/dev/null || echo "  open $GITHUB_URL in a browser"
else
    if command -v xclip >/dev/null 2>&1; then
        xclip -selection clipboard < "$PUB" 2>/dev/null || true
        echo "  public key copied to clipboard"
    fi
    if command -v xdg-open >/dev/null 2>&1; then
        xdg-open "$GITHUB_URL" 2>/dev/null || true
    fi
fi

echo ""
echo "  Add this key at $GITHUB_URL — suggested title: $(hostname -s)"
echo "  (the .pub below only; never share the private key at $KEY)"
cat "$PUB"
echo ""
read -r -p "  Press Enter once the key is added on GitHub... " _
echo ""
echo "  testing connection..."

# GitHub closes the connection with exit 1 even on success, so judge by output.
out="$(ssh -T git@github.com 2>&1 || true)"
if printf '%s\n' "$out" | grep -q 'successfully authenticated'; then
    echo "  OK — GitHub SSH works"
    echo ""
    echo "Push over SSH from an HTTPS clone (the chezmoi repo):"
    echo '  git -C ~/.local/share/chezmoi remote set-url origin git@github.com:JakobHavtorn/dotfiles.git'
else
    echo "  FAILED — GitHub did not accept the key:"
    printf '%s\n' "$out"
    exit 1
fi
