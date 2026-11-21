# dotfiles

chezmoi-based dotfiles.

## Bootstrap

One command, no prerequisites — the repo is public and clones over HTTPS:

```sh
IDENTITY=work sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin" init --apply jakobhavtorn/dotfiles
```

Without `IDENTITY`, you'll be prompted for a machine identity (`work` / `personal`).

agent-skills is public too, so its clone — skills for every harness — succeeds without credentials during the apply. Add `--ssh` to bootstrap over SSH instead; that path needs the key seeded first (below).

### SSH for pushes

The HTTPS clone pulls without auth, but pushing needs a key. The first `chezmoi apply` in a terminal seeds it for you: `run_once_after_06-seed-github-ssh` runs the standalone script — keygen at `~/.ssh/id_github`, browser opens at `github.com/settings/keys`, press Enter once the key is added, and it verifies. An aborted run never blocks the bootstrap; it logs the manual command.

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
printf 'Host github.com\n  AddKeysToAgent yes\n  IdentityFile ~/.ssh/id_github\n  UseKeychain yes\n' > ~/.ssh/config.d/github
ssh -T git@github.com    # expect: Hi JakobHavtorn!
```

Omit `UseKeychain yes` on Linux. Both paths seed exactly what chezmoi manages (`private_dot_ssh/config.d/github.tmpl` + `run_once_after_05-ssh-config`), so the first apply converges with no diff. To push over SSH from an HTTPS clone: `git -C ~/.local/share/chezmoi remote set-url origin git@github.com:JakobHavtorn/dotfiles.git`.

### After the apply

Two optional layers skip non-fatally without credentials:

- `gh auth login` (answer yes to the git credential setup) — enables `gh` usage and HTTPS pushes.
- Add `CORTI_BEARER` to `~/.env`, then run `npx @corti/cli@latest models init --tools opencode,pi --scope global`.

### Homebrew (macOS)

The installer creates `/opt/homebrew` once with sudo — the bootstrap prompts for your password when it reaches this step. Standard (non-admin) accounts need the prefix prepared once by an admin:

```sh
sudo mkdir -p /opt/homebrew && sudo chown -R $(whoami):staff /opt/homebrew
```

A failed Homebrew install never aborts the bootstrap; the log prints the same recovery commands. Every deferred layer self-heals: after Homebrew is installed, simply re-apply — the every-apply steps re-run and the presence facts flip the deferred layers back on:

```sh
eval "$(/opt/homebrew/bin/brew shellenv)"
~/.local/bin/chezmoi apply
```

### Linux prerequisites

A minimal container or fresh box may lack these:

```sh
apt-get update && apt-get install -y --no-install-recommends curl ca-certificates git xz-utils unzip
```

`curl` runs the one-liner, `git` clones the repo, `xz-utils` extracts the fish and node archives (`.tar.xz`), `unzip` extracts the bun archive (`.zip`), `ca-certificates` validates HTTPS to GitHub. macOS has all of these pre-installed.

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
