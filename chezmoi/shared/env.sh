# shellcheck shell=bash
# env.sh — runtime environment helpers for chezmoi scripts
# Source from other scripts: source "{{ .chezmoi.sourceDir }}/shared/env.sh"

# True when running in CI (GitHub Actions, GitLab, etc.). Most CI providers
# export CI=true. This is a runtime check — works in rendered scripts.
is_ci() {
    [[ -n "${CI:-}" ]]
}

# True on macOS (Darwin). Uses `uname` so it works at runtime in rendered
# scripts, not just in chezmoi template conditionals.
is_darwin() {
    [[ "$(uname)" == "Darwin" ]]
}

# True on Linux. Uses `uname` so it works at runtime in rendered scripts.
is_linux() {
    [[ "$(uname)" == "Linux" ]]
}

# Machine architecture (uname -m). Used by remote-tools to warn when
# the manifest arch doesn't match the running arch.
arch() {
    uname -m
}

# Ensure ~/.local/bin is in PATH for chezmoi run scripts. On remote Linux,
# tools (fish, herdr, gh, etc.) are installed rootless to ~/.local/bin by
# run_onchange_before_15-remote-tools.sh.tmpl. Downstream scripts (OMF,
# herdr plugins) find them via `command -v` — without this, they'd need
# ~/.local/bin already in the inherited login shell PATH.
case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) [[ -d "$HOME/.local/bin" ]] && PATH="$HOME/.local/bin:$PATH" ;;
esac
