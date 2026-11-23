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
#
# The guard MUST end in success: this file is sourced under `set -e`, so
# a false-returning compound as the last statement makes `source` itself
# return 1 and kills the sourcing script. On a fresh CI container
# ~/.local/bin doesn't exist yet (remote-tools creates it later), which
# silently failed every linux clean-install since 4075ced (Oct 4) — the
# `[[ -d ]] &&` short-circuit returned 1 from the case, and with it the
# whole file. Hence `if` instead of `&&`.
case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) if [[ -d "$HOME/.local/bin" ]]; then PATH="$HOME/.local/bin:$PATH"; fi ;;
esac

# Homebrew's bin dir — same rationale as ~/.local/bin above: run scripts
# find brew-installed tools via `command -v` even when the invoking shell
# (or chezmoi's own render/apply process) carries no brew PATH — e.g. a
# fresh machine's first apply, where Homebrew lands mid-apply and the
# shell that started chezmoi predates it. Prepend (shellenv order) so
# brew tools keep precedence over system ones.
for _brewbin in /opt/homebrew/bin /usr/local/bin; do
    case ":$PATH:" in
        *":$_brewbin:"*) ;;
        *) if [[ -d "$_brewbin" ]]; then PATH="$_brewbin:$PATH"; fi ;;
    esac
done
unset _brewbin
