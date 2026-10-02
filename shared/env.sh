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
