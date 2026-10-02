#!/usr/bin/env bash
# dump.sh — snapshot current machine state into manifests/.
# Run weekly via launchd (macOS). No auto-commit; review and commit by hand.
#
# Generated manifests are observed state, not declarations: git diff shows what
# the machine consciously drifted, and PR review is the gate. pipx.txt is the
# install declaration consumed by run_onchange_after_70-pipx.sh — dumped from
# the venvs' pipx metadata so git-URL sources and extras survive regeneration;
# a plain 'pipx list' does not expose them.
set -euo pipefail

# launchd sessions get /usr/bin:/bin only; put Homebrew first so brew/go/npm/fish/jq resolve
PATH="/opt/homebrew/bin:/usr/local/bin:${PATH}"
export PATH

cd "$(chezmoi source-path)"

echo "=== dumping machine state ==="

# ---------------------------------------------------------------------------
# Homebrew — brew bundle dump (regenerate Brewfile), then drift + cleanup checks.
# ---------------------------------------------------------------------------
dump_brew() {
    if ! command -v brew >/dev/null 2>&1; then
        echo "  brew not found, skipping"
        return 0
    fi

    echo "  brew bundle dump..."
    brew bundle dump --force --file manifests/Brewfile

    # Drift report — does the machine still satisfy the Brewfile? (report-only)
    # Outdated/missing formulas or corrupt keg-tab dependency data surface here.
    # Repair steps: README, section "Brew repair".
    echo "  brew bundle check..."
    local check_out
    if check_out="$(brew bundle check --file manifests/Brewfile 2>&1)"; then
        echo "  brew dependencies satisfied"
    else
        echo "  brew bundle check FAILED (repair: README, 'Brew repair')"
        printf '%s\n' "$check_out" | sed 's/^/    /' | tail -n 6
    fi

    # Convergence report — what would `brew bundle cleanup` REMOVE?
    # The pipeline is additive-only: deleting a Brewfile line never uninstalls.
    # This dry-run gives weekly visibility into the drift, so a stale entry is
    # noticed and removed by hand (brew bundle cleanup is destructive — never
    # run it without review). Report-only, non-fatal.
    echo "  brew bundle cleanup --dry-run (report-only)..."
    local cleanup_out
    if cleanup_out="$(brew bundle cleanup --dry-run --file manifests/Brewfile 2>&1)"; then
        # brew bundle cleanup --dry-run returns 0 even when it lists removals.
        if [ -n "$cleanup_out" ]; then
            printf '%s\n' "$cleanup_out" | sed 's/^/    /'
        else
            echo "    (nothing to remove)"
        fi
    else
        echo "    cleanup dry-run could not complete"
        printf '%s\n' "$cleanup_out" | sed 's/^/    /' | tail -n 6
    fi
}

# ---------------------------------------------------------------------------
# pipx — install declaration ('name' or 'name|source'), consumed by
# run_onchange_after_70-pipx.sh. Sources come from each venv's pipx metadata
# ('package_or_url' — git URLs, extras); 'pipx list' does not expose them.
# ---------------------------------------------------------------------------
dump_pipx() {
    if [ ! -d "$HOME/.local/pipx/venvs" ]; then
        echo "  pipx not found, skipping"
        return 0
    fi

    echo "  pipx packages..."
    python3 - > manifests/pipx.txt <<'PY'
import glob, json, os

print("# pipx install declaration — consumed by run_onchange_after_70-pipx.sh")
print("# Lines: 'name' or 'name|source'. Dumped from the venvs' pipx metadata")
print("# by scripts/dump.sh; lines starting with # are comments.")
for meta_path in sorted(glob.glob(os.path.expanduser("~/.local/pipx/venvs/*/pipx_metadata.json"))):
    name = meta_path.split("/")[-2]
    main = json.load(open(meta_path)).get("main_package") or {}
    source = main.get("package_or_url")
    print(f"{name}|{source}" if source and source != name else name)
PY
}

# ---------------------------------------------------------------------------
# OMF packages and themes — lines: 'plugin|name' / 'theme|name' (consumed by run_onchange_after_60-omf.sh)
# omf list output is sectioned + tab-separated: parse despite what the old hand-curated comment claimed
# ---------------------------------------------------------------------------
dump_omf() {
    if ! command -v fish >/dev/null 2>&1 || ! fish -c 'type -q omf' >/dev/null 2>&1; then
        echo "  omf not found, skipping"
        return 0
    fi

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
}

# ---------------------------------------------------------------------------
# macOS defaults — observed values for exactly the keys in
# manifests/macos-defaults-keys.txt (the shared artifact). dump.sh reads the
# (domain, key) pairs and calls `defaults read`; the install script reads the
# same file and writes them. No awk-parsing of the install script — the keys
# file is the single source of truth.
# ---------------------------------------------------------------------------
dump_macos_defaults() {
    local keys_file="manifests/macos-defaults-keys.txt"

    if [ ! -f "$keys_file" ] || ! command -v defaults >/dev/null 2>&1; then
        echo "  macOS defaults keys file or defaults not found, skipping"
        return 0
    fi

    echo "  macOS defaults..."
    {
        echo "# macOS defaults — observed values for keys in manifests/macos-defaults-keys.txt (dumped by scripts/dump.sh)"
        # Lines: domain|key|value — read domain+key, ignore value (dump observes live state).
        awk -F'|' '/^[^#]/{print $1 "|" $2}' "$keys_file" | sort -u | while IFS='|' read -r domain key; do
            [ -n "$domain" ] && [ -n "$key" ] || continue
            value="$(defaults read "$domain" "$key" 2>/dev/null || echo "(absent)")"
            printf '%s %s = %s\n' "$domain" "$key" "$value"
        done
    } > manifests/macos-defaults.txt
}

# ---------------------------------------------------------------------------
# Run all sections in sequence.
# ---------------------------------------------------------------------------
dump_brew
dump_pipx
dump_omf
dump_macos_defaults
./scripts/check-bootstrap.sh || echo "  (non-fatal: incomplete bootstrap reported above)"

echo ""
git diff --stat
echo ""
echo "review, curate, commit by hand."
