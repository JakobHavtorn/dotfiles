#!/usr/bin/env bash
# dump.sh — snapshot current machine state into manifests/.
# Run daily via launchd (macOS); dump-pr.sh then commits to a dated branch
# and opens a PR — review happens there.
#
# Generated manifests are observed state, not declarations: git diff shows what
# the machine consciously drifted, and PR review is the gate. pipx.txt is the
# install declaration consumed by run_onchange_after_70-pipx.sh — dumped from
# the venvs' pipx metadata so git-URL sources and extras survive regeneration;
# a plain 'pipx list' does not expose them.
set -euo pipefail

# launchd sessions get /usr/bin:/bin only; put Homebrew first so brew/go/npm/fish/jq resolve,
# and ~/.local/bin so brew bundle dump finds `code` (linked by 19-macos-apps) for vscode lines
PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:${PATH}"
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
    # This dry-run gives daily visibility into the drift, so a stale entry is
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
# Obsidian — snapshot vault config (.obsidian/*.json) and plugin configs
# (plugins/*/manifest.json + data.json). Excludes workspace state and
# binary plugin files (main.js, styles.css). Not the notes themselves.
# ---------------------------------------------------------------------------
dump_obsidian() {
    local vault="$HOME/Library/Mobile Documents/iCloud~md~obsidian/Documents/Zettelkasten"
    local obs_dir="$vault/.obsidian"
    local dest="manifests/obsidian"

    if [ ! -d "$obs_dir" ]; then
        echo "  obsidian vault not found, skipping"
        return 0
    fi

    echo "  obsidian config..."

    # Top-level config files (portable, not machine-specific)
    local configs=(
        app.json community-plugins.json core-plugins.json core-plugins-migration.json
        daily-notes.json graph.json hotkeys.json templates.json types.json
        workspaces.json zk-prefixer.json
    )

    mkdir -p "$dest"
    for f in "${configs[@]}"; do
        [ -f "$obs_dir/$f" ] && cp "$obs_dir/$f" "$dest/$f"
    done

    # Plugin manifests + data.json (config only; skip main.js/styles.css)
    rm -rf "$dest/plugins"
    mkdir -p "$dest/plugins"
    for d in "$obs_dir/plugins/"*/; do
        local plugin
        plugin=$(basename "$d")
        mkdir -p "$dest/plugins/$plugin"
        [ -f "$d/manifest.json" ] && cp "$d/manifest.json" "$dest/plugins/$plugin/manifest.json"
        [ -f "$d/data.json" ] && cp "$d/data.json" "$dest/plugins/$plugin/data.json"
    done
}

# ---------------------------------------------------------------------------
# iTerm2 — settings plist under an allowlist: the committed manifest IS
# the allowlist. Each dump refreshes values for tracked keys only; live
# keys not yet tracked are reported for review and never captured; keys
# gone from the live domain keep their last known value (reported) so a
# second machine's dump can never silently drop a setting. Bootstrap
# (first capture on a machine with no manifest): strip the machine-local
# and junk classes — NoSync* (incl. search history — the known leak
# class), NS*/SU*/kCPK*/PM* (AppKit, Sparkle, color/print panels), window
# arrangements, command-palette favorites, version stamps, folder-mode
# pointers. The install side (run_onchange_after_87-iterm2-config)
# imports the manifest only on machines with no settings yet; dump is
# the source of truth here.
# ---------------------------------------------------------------------------
dump_iterm2() {
    if [ "$(uname)" != "Darwin" ] || ! defaults read com.googlecode.iterm2 >/dev/null 2>&1; then
        echo "  iterm2 settings not found, skipping"
        return 0
    fi

    echo "  iterm2 settings..."
    mkdir -p manifests/iterm2
    python3 - <<'PY'
import os, plistlib, subprocess, tempfile

MANIFEST = "manifests/iterm2/com.googlecode.iterm2.plist"
JUNK_PREFIXES = ("NoSync", "NS", "SU", "kCPK", "PM")
JUNK_KEYS = {
    "Window Arrangements", "kCPFavoritesUserDefaultsKey",
    "LoadPrefsFromCustomFolder", "PrefsCustomFolder", "iTerm Version",
}

def is_junk(k):
    return k.startswith(JUNK_PREFIXES) or k in JUNK_KEYS

tmp = tempfile.mktemp(suffix=".plist")
subprocess.run(["defaults", "export", "com.googlecode.iterm2", tmp], check=True)
with open(tmp, "rb") as f:
    live = plistlib.load(f)
os.unlink(tmp)

if os.path.exists(MANIFEST):
    with open(MANIFEST, "rb") as f:
        kept = plistlib.load(f)
    tracked = set(kept)
    for k, v in live.items():
        if k in tracked:
            kept[k] = v
    for k in sorted(set(live) - tracked):
        if not is_junk(k):
            print(f"    iterm2 new key (not tracked — add deliberately if wanted): {k}")
    for k in sorted(tracked - set(live)):
        print(f"    iterm2 key gone (last value kept — remove deliberately if dead): {k}")
else:
    kept = {k: v for k, v in live.items() if not is_junk(k)}
    print(f"    iterm2 bootstrap capture: {len(kept)} keys")

with open(MANIFEST, "wb") as f:
    plistlib.dump(kept, f, fmt=plistlib.FMT_XML)
PY
}

# ---------------------------------------------------------------------------
# Karabiner-Elements — karabiner.json (the whole config). Same rule as
# iterm2: install only where absent; dump observes the source machine.
# ---------------------------------------------------------------------------
dump_karabiner() {
    local src="$HOME/.config/karabiner/karabiner.json"
    if [ ! -f "$src" ]; then
        echo "  karabiner config not found, skipping"
        return 0
    fi

    echo "  karabiner config..."
    mkdir -p manifests/karabiner
    cp "$src" manifests/karabiner/karabiner.json
}

# ---------------------------------------------------------------------------
# Run all sections in sequence.
# ---------------------------------------------------------------------------
dump_brew
dump_pipx
dump_omf
dump_macos_defaults
dump_obsidian
dump_iterm2
dump_karabiner
../scripts/check-bootstrap.sh || echo "  (non-fatal: incomplete bootstrap reported above)"

echo ""
git diff --stat
echo ""
echo "dump complete. dump-pr.sh will open a PR if there are changes."
