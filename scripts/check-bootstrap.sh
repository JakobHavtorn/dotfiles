#!/usr/bin/env bash
# check-bootstrap.sh — detect an interrupted chezmoi apply.
#
# An interrupted `chezmoi apply` stages run_* scripts in entryState, but records
# scriptState[runAt] only once they actually ran. A later unchanged-render apply
# then SKIPS those scripts silently, leaving the bootstrap incomplete.
#
# Platform-agnostic (needs only chezmoi + python3). Called from scripts/dump.sh
# (non-fatal) and CI (post-apply assertion).
# Exits 0 if every staged run_ script has a runAt record; 1 if incomplete.
set -euo pipefail

if ! command -v chezmoi >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1; then
    echo "  chezmoi or python3 not found, skipping bootstrap check"
    exit 0
fi

echo "  run-script completeness..."

python3 - <<'PY'
import json, subprocess, sys

try:
    state = json.loads(subprocess.run(
        ["chezmoi", "state", "dump", "--format=json"],
        capture_output=True, text=True, check=True,
    ).stdout)
except Exception:
    print("  completeness ERROR: 'chezmoi state dump' could not be parsed", file=sys.stderr)
    sys.exit(1)

staged, ran = {}, {v.get("name", "") for v in state.get("scriptState", {}).values()}
for key in state.get("entryState", {}):
    base = key.rsplit("/", 1)[-1]
    # run_* sources stage under their plain name, always number-prefixed
    # (e.g. 'run_onchange_before_15-...' -> '15-...sh'). shared/ helpers are
    # ignored via .chezmoiignore and never stage; the digit filter is defensive.
    if base.endswith(".sh") and base[:1].isdigit():
        staged[base] = key
unrun = [b for b in sorted(staged) if b not in ran]
if unrun:
    print("  INCOMPLETE — staged but never run (later applies skip them silently):", file=sys.stderr)
    for b in unrun:
        print(f"    {b}   (state key: {staged[b]})", file=sys.stderr)
    print("    repair: chezmoi state delete --bucket=entryState --key=<state key>; chezmoi diff && chezmoi apply", file=sys.stderr)
    print("    partial apply log: ~/.local/state/dotfiles/last-apply.log", file=sys.stderr)
    sys.exit(1)
else:
    print("  ok — every staged run_ script has a runAt record")
PY
