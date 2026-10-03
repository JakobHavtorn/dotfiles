# dotfiles

chezmoi-based dotfiles. Private repo.

## Bootstrap

```sh
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply --ssh jakobhavtorn/dotfiles
```

**Prerequisites:**

- **Linux only** — a minimal container or fresh box may lack these:
  ```sh
  apt-get update && apt-get install -y --no-install-recommends curl ca-certificates git xz-utils
  ```
  `curl` runs the one-liner, `git` clones the repo, `xz-utils` extracts the fish archive (`.tar.xz`), `ca-certificates` validates HTTPS to GitHub. macOS has all of these pre-installed.
- **SSH auth** — the repo is private. Either give the box its own key, or bootstrap through one agent-forwarded session (`ssh -A <host>` first).
- **Role prompt** — you'll be prompted for a machine role (`work` / `personal` / `remote`).

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

## Roles

| Role | Gets |
|---|---|
| `work` | Full setup: fish, git, opencode, homebrew, k9s, macOS defaults |
| `personal` | Same as work (identity differs via templates) |
| `remote` | Reduced: fish config, git, opencode, rootless CLI tools. No homebrew, no casks, no macOS defaults. |

## Layout

See [AGENTS.md](AGENTS.md) for the repo layout, conventions, and agent guidelines.
