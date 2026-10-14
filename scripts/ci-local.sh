#!/usr/bin/env bash
# ci-local.sh — lint checks for the dotfiles repo.
#
# Single source of truth for both local and CI runs.
# Called from .github/workflows/lint.yml and runnable as scripts/ci-local.sh.
#
# Usage: scripts/ci-local.sh
#
# Checks:
#   1. JSON template files parse as valid JSON
#   2. Shellcheck on all .sh files (severity: warning, matching CI)
#   3. set -euo pipefail present in all executable scripts
#   4. Chezmoi templates render for both identities (work, personal)
#
# Does NOT run the clean-install workflows — those need a fresh OS
# and have side effects unsuitable for a live machine.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

# shellcheck disable=SC1091
source "$REPO_ROOT/chezmoi/shared/log.sh"

_fail=0

log_section "lint checks"

# ---------------------------------------------------------------------------
# 1. Validate JSON template files
# ---------------------------------------------------------------------------
log_info "validating JSON templates..."
# Intentionally a list — adding more JSON templates later is trivial.
# shellcheck disable=SC2043
for _f in chezmoi/dot_config/opencode/cli.json.tmpl; do
    [[ -f "$_f" ]] || continue
    if python3 -c "import json; json.load(open('$_f'))" 2>/dev/null; then
        log_ok "$_f: valid JSON"
    else
        log_err "$_f: invalid JSON"
        _fail=1
    fi
done
unset _f

# ---------------------------------------------------------------------------
# 2. Shellcheck (severity: warning — same as CI)
# ---------------------------------------------------------------------------
if command -v shellcheck >/dev/null 2>&1; then
    log_info "running shellcheck..."
    # Only .sh files; .sh.tmpl contains Go template syntax ({{ }}) that
    # is not valid bash. CI's action has the same behavior.
    _sc_files=()
    while IFS= read -r _f; do
        _sc_files+=("$_f")
    done < <(find chezmoi scripts -name '*.sh' \
        | grep -v '/shared/log.sh$' \
        | grep -v '/shared/env.sh$' \
        | grep -v '/shared/manifest.sh$' \
        | sort)
    if [[ ${#_sc_files[@]} -gt 0 ]]; then
        if shellcheck --severity=warning "${_sc_files[@]}" 2>&1; then
            log_ok "shellcheck (${#_sc_files[@]} files)"
        else
            log_err "shellcheck found issues"
            _fail=1
        fi
    fi
    unset _sc_files _f
else
    log_warn "shellcheck not found — skipping"
fi

# ---------------------------------------------------------------------------
# 3. Verify set -euo pipefail in all executable scripts
# ---------------------------------------------------------------------------
log_info "checking set -euo pipefail..."
_missing=0
while IFS= read -r _f; do
    [[ -f "$_f" ]] || continue
    case "$_f" in
        */shared/log.sh|*/shared/env.sh|*/shared/manifest.sh) continue ;;
    esac
    if ! grep -q 'set -euo pipefail' "$_f"; then
        log_err "missing 'set -euo pipefail': $_f"
        _missing=1
    fi
done < <(find chezmoi/run_once_* chezmoi/run_onchange_* chezmoi/run_after_* scripts/*.sh chezmoi/shared/*.sh 2>/dev/null | sort)
if [[ $_missing -eq 0 ]]; then
    log_ok "all scripts have 'set -euo pipefail'"
else
    _fail=1
fi
unset _f _missing

# ---------------------------------------------------------------------------
# 4. Render templates for both identities
# ---------------------------------------------------------------------------
if command -v chezmoi >/dev/null 2>&1; then
    log_info "rendering templates for both identities..."
    _chezmoi_config="$(mktemp)"
    _chezmoi_cleanup() { rm -f "$_chezmoi_config"; }
    trap '_chezmoi_cleanup' EXIT
    for _identity in work personal; do
        # Write a temporary chezmoi config with the identity, matching CI's
        # approach. .chezmoidata.yaml (identities map) is always loaded from
        # the source dir, so only .identity needs to be set here.
        printf 'sourceDir = "%s"\n[data]\nidentity = "%s"\n' "$REPO_ROOT" "$_identity" > "$_chezmoi_config"
        _tmpl_fail=0
        while IFS= read -r _f; do
            if ! chezmoi execute-template --config "$_chezmoi_config" --config-format toml < "$_f" > /dev/null 2>&1; then
                log_err "FAILED: $_f (identity=$_identity)"
                chezmoi execute-template --config "$_chezmoi_config" --config-format toml < "$_f" 2>&1 || true
                _tmpl_fail=1
            fi
        done < <(find . -name '*.tmpl' -not -path './.git/*' -not -name '.chezmoi.toml.tmpl' | sort)
        if [[ $_tmpl_fail -eq 0 ]]; then
            log_ok "templates render (identity=$_identity)"
        else
            _fail=1
        fi
    done
    unset _identity _tmpl_fail _f
    _chezmoi_cleanup
    trap - EXIT
    unset _chezmoi_config _chezmoi_cleanup
else
    log_warn "chezmoi not found — skipping template rendering"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
if [[ $_fail -eq 0 ]]; then
    log_ok "all checks passed"
    exit 0
else
    log_err "some checks failed"
    exit 1
fi
