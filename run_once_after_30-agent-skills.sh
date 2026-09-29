#!/usr/bin/env bash
set -euo pipefail

# Clone agent-skills and link skills into opencode.
# Config linking is handled by dotfiles/chezmoi, not agent-skills.

AGENT_SKILLS_DIR="${AGENT_SKILLS_DIR:-$HOME/.agent-skills}"
OPENCODE_CONFIG_DIR="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"

echo "=== agent-skills bootstrap ==="

if ! command -v git >/dev/null 2>&1; then
    echo "  WARNING: git not found — skipping agent-skills. Install git to enable."
    exit 0
fi

# Private repo — verify auth before attempting clone.
# On remote/CI without SSH keys or token, skip gracefully.
if [[ -d "$AGENT_SKILLS_DIR/.git" ]]; then
    echo "  updating $AGENT_SKILLS_DIR ..."
    git -C "$AGENT_SKILLS_DIR" pull --ff-only || {
        echo "  WARNING: pull failed — keeping existing checkout."
    }
else
    echo "  cloning to $AGENT_SKILLS_DIR ..."
    if ! git clone https://github.com/JakobHavtorn/agent-skills.git "$AGENT_SKILLS_DIR" 2>&1; then
        echo "  WARNING: clone failed (private repo, no auth) — skipping agent-skills."
        echo "  To enable: set up SSH keys or configure a GitHub token."
        exit 0
    fi
fi

# Link skills (config linking is handled by chezmoi/dotfiles)
if command -v python3 >/dev/null 2>&1; then
    python3 "$AGENT_SKILLS_DIR/bin/skillctl" link --agent opencode --force
else
    echo "  WARNING: python3 not found — skipping skill linking. Install via uv to enable."
fi

# Link agents directory
if [[ -d "$AGENT_SKILLS_DIR/agents" ]]; then
    mkdir -p "$OPENCODE_CONFIG_DIR"
    ln -sfh "$AGENT_SKILLS_DIR/agents" "$OPENCODE_CONFIG_DIR/agents" 2>/dev/null || {
        [[ -e "$OPENCODE_CONFIG_DIR/agents" && ! -L "$OPENCODE_CONFIG_DIR/agents" ]] && mv "$OPENCODE_CONFIG_DIR/agents" "$OPENCODE_CONFIG_DIR/agents.bak"
        ln -sf "$AGENT_SKILLS_DIR/agents" "$OPENCODE_CONFIG_DIR/agents"
    }
    echo "  linked agents/"
fi

echo "=== done ==="
