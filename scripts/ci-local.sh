#!/usr/bin/env bash
# ci-local.sh — run the same fast checks as .github/workflows/lint.yml locally.
#
# Usage: scripts/ci-local.sh
#
# Checks:
#   1. JSON template files render to valid JSON
#   2. Shellcheck on all shell scripts
#   3. set -euo pipefail present in all executable scripts
#   4. Chezmoi templates render for both identities (work, personal)
#
# Does NOT run the clean-install workflows — those need a fresh OS
# and have side effects unsuitable for a live machine.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

# Source shared logging for consistent output style.
# shellcheck disable=SC1091
source "$REPO_ROOT/chezmoi/shared/log.sh"

_fail=0

log_section "ci-local (lint checks)"

# ---------------------------------------------------------------------------
# 1. Validate JSON template files
# ---------------------------------------------------------------------------
log_info "validating JSON templates..."
    # Intentionally a list — adding more JSON templates later is trivial.
    # shellcheck disable=SC2043
    for f in chezmoi/dot_config/opencode/cli.json.tmpl; do
    [[ -f "$f" ]] || continue
    if python3 -c "import json; json.load(open('$f'))" 2>/dev/null; then
        log_ok "$f: valid JSON"
    else
        log_err "$f: invalid JSON"
        _fail=1
    fi
done

# ---------------------------------------------------------------------------
# 2. Shellcheck
# ---------------------------------------------------------------------------
if command -v shellcheck >/dev/null 2>&1; then
    log_info "running shellcheck..."
    # Shellcheck only .sh files — .sh.tmpl files contain Go template
    # syntax ({{ }}) that shellcheck can't parse.  CI's action has the
    # same behavior: it detects shell scripts by extension.
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
    for _identity in work personal; do
        _tmpl_fail=0
        while IFS= read -r _f; do
            if ! chezmoi execute-template --override-data "{\"identity\":\"$_identity\"}" < "$_f" > /dev/null 2>&1; then
                log_err "FAILED: $_f (identity=$_identity)"
                chezmoi execute-template --override-data "{\"identity\":\"$_identity\"}" < "$_f" 2>&1 || true
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
else
    log_warn "chezmoi not found — skipping template rendering"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
if [[ $_fail -eq 0 ]]; then
    log_ok "ci-local: all checks passed"
    exit 0
else
    log_err "ci-local: some checks failed"
    exit 1
fi
