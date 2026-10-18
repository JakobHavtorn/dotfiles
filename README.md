# dotfiles

chezmoi-based dotfiles. Private repo.

## Bootstrap

Promptless (recommended):

```sh
IDENTITY=work sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin" init --apply --ssh jakobhavtorn/dotfiles
```

Without `IDENTITY`, you'll be prompted for a machine identity (`work` / `personal`).

**Prerequisites:**

- **Linux only** — a minimal container or fresh box may lack these:
  ```sh
  apt-get update && apt-get install -y --no-install-recommends curl ca-certificates git xz-utils unzip
  ```
  `curl` runs the one-liner, `git` clones the repo, `xz-utils` extracts the fish and node archives (`.tar.xz`), `unzip` extracts the bun archive (`.zip`), `ca-certificates` validates HTTPS to GitHub. macOS has all of these pre-installed.
- **SSH auth** — the repo is private. Either give the box its own key, or bootstrap through one agent-forwarded session (`ssh -A <host>` first).

Optional personal-layer steps (`corti models init`, agent-skills clone) are non-fatal: without their credentials they log an error and the bootstrap continues. Re-run them manually once credentials are in place, or `chezmoi update`.

## Usage

```sh
chezmoi diff     # review pending changes before applying
chezmoi apply    # apply changes
chezmoi update   # git pull + apply
```

## Operational habits

**Always diff before apply.** There is no rollback and no transaction — a failure on
file 40 of 60 leaves the first 39 written. The diff is the safety net.

```fish
abbr -a cza 'chezmoi diff; and read -P "apply? " -n1 c; and test "$c" = y; and chezmoi apply --no-pager'
```

`--no-pager` avoids a [known deadlock](https://github.com/twpayne/chezmoi/issues/4874) where the diff pager and the overwrite prompt both grab the TTY. Without it, the prompt vanishes on first keystroke and chezmoi hangs.

**Edited a `run_once` script that already ran?** It will not re-run — chezmoi tracks
execution in a local state DB. The escape hatch:

```
chezmoi state delete-bucket --bucket=scriptState
```

This bites everyone exactly once.

## Brew repair

When `chezmoi apply` fails inside `20-brew-bundle`, or the weekly dump reports
`brew bundle check` failing, repair by hand. `brew update` alone does not fix
it. The two failure classes previously seen:

1. **Stale keg-tab metadata** — `brew bundle check --verbose` shows circular
   dependency warnings between unrelated formulae (e.g., libtiff/webp listing
   each other). The fix is `brew reinstall <offending-formula>`, which
   regenerates the tab's `INSTALL_RECEIPT.json`.
2. **Orphaned manually-installed formulae** — a keg not declared in
   `manifests/Brewfile` can still own files other formulae want; e.g., a
   pre-repo `anomalyco/tap/opencode` 1.x held `bin/opencode` and every
   `opencode-v2` upgrade then failed to link. Uninstall the orphan (or adopt
   it into the Brewfile).

Then re-run and expect a quiet check before applying:

```sh
brew bundle install --file chezmoi/manifests/Brewfile
brew bundle check
chezmoi diff && chezmoi apply
```

## Identity

| Identity | Git author |
|---|---|
| `work` | Jakob Havtorn <jdh@corti.ai> |
| `personal` | Jakob Havtorn <havtorn93@gmail.com> |

Platform differences (Homebrew, macOS defaults, rootless tools, k9s) are detected automatically from the OS — no manual role selection needed.

## Pre-commit hooks

Install hooks after cloning:

```sh
pre-commit install
```

Runs all four `ci-local.sh` checks (JSON, shellcheck, pipefail, template rendering) on every commit. Bypass with `git commit --no-verify`.

## Local CI

```sh
scripts/ci-local.sh
```

Same checks as pre-commit, runnable on demand. CI (`.github/workflows/lint.yml`) calls this script too — single source of truth.

## Layout

See [AGENTS.md](AGENTS.md) for the repo layout, conventions, and agent guidelines.
