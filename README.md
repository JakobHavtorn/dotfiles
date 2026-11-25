# dotfiles

chezmoi-based dotfiles.

## Bootstrap

One command, no prerequisites — the repo is public and clones over HTTPS:

```sh
IDENTITY=work sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin" init --apply jakobhavtorn/dotfiles
```

Without `IDENTITY`, you'll be prompted for a machine identity (`work` / `personal`).

agent-skills is public too, so its clone — skills for every harness — succeeds without credentials during the apply. Add `--ssh` to bootstrap over SSH instead; that path needs the key seeded first (below).

### Before, during, and after the run

Nothing blocks the run — missing pieces defer, and the report (the last step of every apply) replays every warning and failure from the run, prints what is left with its fix, and points at the full log. To finish in one pass:

**Before running:**

- macOS: admin credentials at hand — the run elevates once per machine (Homebrew prefix, Karabiner-Elements, fish as the login shell). Fresh machines see the prefix elevation on the first apply; Karabiner and fish on a later one, once Homebrew lands them.
- A GitHub account you can sign into — the browser opens to add a new SSH key.
- `CORTI_BEARER` in `~/.env` (from your password manager) — without it the Corti model wiring defers.
- Linux: `curl ca-certificates git xz-utils unzip` (see [Linux prerequisites](#linux-prerequisites)).
- The machine identity: `work` or `personal` — `IDENTITY=work` in the env skips the prompt.

**During the run — input is expected at:**

- The identity prompt, when `IDENTITY` is not set.
- The elevation prompt on macOS (log line: `approve the elevation prompt...`).
- The GitHub SSH step: the public key is on the clipboard, the browser opens at `github.com/settings/keys` — add the key, then press Enter in the terminal.
- Homebrew's installer prompts — only when the prefix could not be prepared beforehand.

Headless applies skip the interactive steps and print the manual commands instead. Opt-outs: `SKIP_HOMEBREW_INSTALL`, `SKIP_GITHUB_SSH_SEED`.

**After the run:**

- Read the report's summary: warnings and failures from the run, deferred layers with their fixes, and the log path. Fix, then re-apply — deferred layers self-heal.
- Apply logs live at `~/.local/state/dotfiles/last-apply.log`; the previous apply sits alongside as `previous-apply.log`.
- Added `CORTI_BEARER` to `~/.env` after the run? Re-apply — the models wiring re-runs once the bearer is present — and restart the opencode service if it was started earlier: services keep the environment they launched with.
- Sign into iCloud and let the Obsidian vault sync, then re-apply.
- `gh auth login` (answer yes to the git credential setup) — enables `gh`; pushes already work over the seeded SSH key.
- Open new terminal windows for the login shell and PATH changes; restart opencode for config changes.
- Karabiner-Elements asks to approve its driver on first launch (macOS).
- A few macOS settings (e.g. Ctrl+Scroll zoom) may need one logout and login to take effect.

### SSH for pushes

The HTTPS clone pulls without auth, but pushing needs a key. Every terminal `chezmoi apply` seeds it for you: `run_after_06-seed-github-ssh` runs the standalone script — keygen at `~/.ssh/id_github`, browser opens at `github.com/settings/keys`, press Enter once the key is added, and it verifies; it skips once the key exists. An aborted run never blocks the bootstrap; it logs the manual command.

Headless applies (CI, cron) skip the interactive step — seed manually whenever you like, before or after the bootstrap:

```sh
bash <(curl -fsLS https://raw.githubusercontent.com/JakobHavtorn/dotfiles/main/scripts/seed-github-ssh.sh)
```

`scripts/seed-github-ssh.sh` is self-contained: it generates the key at `~/.ssh/id_github`, seeds the host block, copies the public key to the clipboard, opens `github.com/settings/keys` in the browser, waits for you to add the key, then verifies the connection. Seeding before the bootstrap is also the prerequisite for the `--ssh` clone variant.

**Paste block** — works with nothing but a shell:

```sh
ssh-keygen -t ed25519 -C "$USER@$(hostname -s)" -f ~/.ssh/id_github
cat ~/.ssh/id_github.pub    # add at github.com/settings/keys — the .pub only, never the private key
mkdir -p ~/.ssh/config.d
printf 'Include config.d/*\n' >> ~/.ssh/config
printf 'Host github.com\n  AddKeysToAgent yes\n  IdentityFile ~/.ssh/id_github\n  UseKeychain yes\n\n' > ~/.ssh/config.d/github
ssh -T git@github.com    # expect: Hi JakobHavtorn!
```

Omit `UseKeychain yes` on Linux. Both paths seed exactly what chezmoi manages (`private_dot_ssh/config.d/github.tmpl` + `run_once_after_05-ssh-config`), so the first apply converges with no diff. To push over SSH from an HTTPS clone: `git -C ~/.local/share/chezmoi remote set-url origin git@github.com:JakobHavtorn/dotfiles.git`.

### Homebrew (macOS)

Creating `/opt/homebrew` needs root once:

- **Admin accounts**: the bootstrap prompts for your password when it reaches this step.
- **Regular accounts** (a separate admin account exists, e.g. `jdh-admin`): the bootstrap handles it. `run_before_09-privileged-preflight` detects the missing prefix during the apply and prepares it with one elevation — on regular accounts it opens the native administrator dialog, the same one application updaters show; enter the admin account's credentials. Settled machines never prompt (pure dir-test guards). Manual fallback if elevation fails:

  ```sh
  sudo mkdir -p /opt/homebrew && sudo chown -R $(id -un):$(id -gn) /opt/homebrew
  ```

  The popup asks for the `jdh-admin` credentials. The prefix must end up owned by you — an admin-owned prefix breaks user-level brew. With a user-owned prefix, the installer needs no sudo at all.

GUI casks install to `~/Applications` (`appdir` in the Brewfile), so nothing else ever needs elevation. A failed Homebrew install never aborts the bootstrap; the log prints the same recovery commands. Every deferred layer self-heals: after Homebrew is installed, simply re-apply — the every-apply steps re-run and the presence facts flip the deferred layers back on:

```sh
eval "$(/opt/homebrew/bin/brew shellenv)"
~/.local/bin/chezmoi apply
```

### Linux prerequisites

A minimal container or fresh box may lack these:

```sh
apt-get update && apt-get install -y --no-install-recommends curl ca-certificates git xz-utils unzip
```

`curl` runs the one-liner, `git` clones the repo, `xz-utils` extracts the fish and node archives (`.tar.xz`), `unzip` extracts the bun archive (`.zip`), `ca-certificates` validates HTTPS to GitHub. macOS needs none of them — darwin installs fish, node, and bun via Homebrew instead of extracting archives.

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

When the apply log reports failed entries inside `20-brew-bundle` (non-fatal), or the daily dump reports
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
brew bundle check --file chezmoi/manifests/Brewfile
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

The ci-local.sh checks, runnable on demand; pre-commit adds hygiene hooks on top. CI (`.github/workflows/lint.yml`) calls this script too — single source of truth.

## Layout

See [AGENTS.md](AGENTS.md) for the repo layout, conventions, and agent guidelines.
