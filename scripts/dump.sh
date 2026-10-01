#!/usr/bin/env bash
# dump.sh — snapshot current machine state into manifests/.
# Run weekly via launchd (macOS). No auto-commit; review and commit by hand.
#
# Generated manifests are observed state, not declarations: git diff shows what
# the machine consciously drifted, and PR review is the gate. Marked exceptions:
# pipx.txt is an install declaration consumed by run_onchange_after_70-pipx.sh —
# dumping it would resurrect packages deliberately removed, re-installing them on
# the next apply. It stays hand-curated.
set -euo pipefail

# launchd sessions get /usr/bin:/bin only; put Homebrew first so brew/go/npm/fish/jq resolve
PATH="/opt/homebrew/bin:/usr/local/bin:${PATH}"
export PATH

cd "$(chezmoi source-path)"

echo "=== dumping machine state ==="

# Homebrew
if command -v brew >/dev/null 2>&1; then
    echo "  brew bundle dump..."
    brew bundle dump --force --file manifests/Brewfile
    # Drift report — does the machine still satisfy the Brewfile? (report-only)
    # Outdated/missing formulas or corrupt keg-tab dependency data surface here.
    # Repair steps: README, section "Brew repair".
    echo "  brew bundle check..."
    if check_out="$(brew bundle check --file manifests/Brewfile 2>&1)"; then
        echo "  brew dependencies satisfied"
    else
        echo "  brew bundle check FAILED (repair: README, 'Brew repair')"
        printf '%s\n' "$check_out" | sed 's/^/    /' | tail -n 6
    fi
else
    echo "  brew not found, skipping"
fi

# pipx: not dumped. manifests/pipx.txt is the install DECLARATION consumed by
# run_onchange_after_70-pipx.sh — regenerating it from 'pipx list' would resurrect
# packages deliberately removed (markitdown, poetry), reinstalling them next apply.

# OMF packages and themes — lines: 'plugin|name' / 'theme|name' (consumed by run_onchange_after_60-omf.sh)
# omf list output is sectioned + tab-separated: parse despite what the old hand-curated comment claimed
if command -v fish >/dev/null 2>&1 && fish -c 'type -q omf' >/dev/null 2>&1; then
    echo "  OMF packages..."
    {
        echo "# omf packages and themes — lines: 'plugin|name' / 'theme|name' (dumped by scripts/dump.sh)"
        fish -c 'omf list' | awk '
            { gsub(/\033\[[0-9;]*m/, "") }
            /^Plugins/ { mode="plugin"; next }
            /^Themes/  { mode="theme";  next }
            NF==0      { next }
            { print mode "|" $1 }
        ' | sort
    } > manifests/omf.txt
else
    echo "  omf not found, skipping"
fi

# Go tools — lines: 'package@version' (binary's own build metadata via 'go version -m')
if command -v go >/dev/null 2>&1; then
    echo "  go tools..."
    gobin="$(go env GOBIN 2>/dev/null || true)"
    [ -n "$gobin" ] || gobin="$(go env GOPATH)/bin"
    {
        echo "# go tools in $gobin — reinstall via 'go install <line>@<version>' (dumped by scripts/dump.sh)"
        for binfile in "$gobin"/*; do
            [ -f "$binfile" ] || continue
            go version -m "$binfile" 2>/dev/null | awk -F'\t' '
                $2=="path" { p=$3; next }
                $2=="mod" && ($3==p || index(p, $3)==1) { print p "@" $4; exit }
            '
        done | sort -u
    } > manifests/go-tools.txt
else
    echo "  go not found, skipping"
fi

# npm globals — lines: 'name@version'
if command -v npm >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    echo "  npm globals..."
    {
        echo "# npm global packages — lines: 'name@version', reinstall via 'npm install -g <name>@<version>' (dumped by scripts/dump.sh)"
        npm ls -g --depth=0 --json | jq -r '
            (.dependencies // {}) | to_entries[]
            | "\(.key)@\(.value.version // "unknown")"
        ' | sort -u
    } > manifests/npm-globals.txt
else
    echo "  npm or jq not found, skipping"
fi

# macOS defaults — observed values for exactly the keys run_once_after_90-macos-defaults.sh.tmpl declares
# Single source of truth: the (domain, key) pairs are parsed from that script, never duplicated here.
# Manual System Settings edits outside these keys are not captured — extend the declared script instead.
if [ -f run_once_after_90-macos-defaults.sh.tmpl ] && command -v defaults >/dev/null 2>&1; then
    echo "  macOS defaults..."
    {
        echo "# macOS defaults — observed values for the keys run_once_after_90-macos-defaults.sh.tmpl declares (dumped by scripts/dump.sh)"
        awk '/^defaults write /{print $3 "|" $4}' run_once_after_90-macos-defaults.sh.tmpl | sort -u | while IFS='|' read -r domain key; do
            value="$(defaults read "$domain" "$key" 2>/dev/null || echo "(absent)")"
            printf '%s %s = %s\n' "$domain" "$key" "$value"
        done
    } > manifests/macos-defaults.txt
else
    echo "  defaults not found, skipping"
fi

# Bootstrap completeness — an interrupted `chezmoi apply` stages run_* scripts
# in entryState, but records scriptState[runAt] only once they actually ran.
# A later unchanged-render apply then SKIPS those scripts silently, leaving the
# bootstrap incomplete. Report any script staged-but-never-run (non-fatal).
if command -v chezmoi >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
    echo "  run-script completeness..."
    python3 - <<'PY' || echo "  completeness ERROR: 'chezmoi state dump' could not be parsed"
import json, subprocess, sys

state = json.loads(subprocess.run(
    ["chezmoi", "state", "dump", "--format=json"],
    capture_output=True, text=True, check=True,
).stdout)
staged, ran = {}, {v.get("name", "") for v in state.get("scriptState", {}).values()}
for key in state.get("entryState", {}):
    base = key.rsplit("/", 1)[-1]
    # run_* sources stage under their plain name, always number-prefixed
    # (e.g. 'run_onchange_before_15-...' -> '15-...sh'); sourced helpers like
    # shared/log.sh also stage as *.sh but carry no number prefix.
    if base.endswith(".sh") and base[:1].isdigit():
        staged[base] = key
unrun = [b for b in sorted(staged) if b not in ran]
if unrun:
    print("  INCOMPLETE — staged but never run (later applies skip them silently):", file=sys.stderr)
    for b in unrun:
        print(f"    {b}   (state key: {staged[b]})", file=sys.stderr)
    print("    repair: chezmoi state delete --bucket=entryState --key=<state key>; chezmoi diff && chezmoi apply", file=sys.stderr)
else:
    print("  ok — every staged run_ script has a runAt record")
PY
else
    echo "  chezmoi or python3 not found, skipping"
fi

echo ""
git diff --stat
echo ""
echo "review, curate, commit by hand."
