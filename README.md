# dotfiles

chezmoi-based dotfiles. Private repo.

## Bootstrap

```sh
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply --ssh jakobhavtorn/dotfiles
```

The repo is private: the machine needs SSH auth against GitHub. Either give the box its own key, or bootstrap through one agent-forwarded session (`ssh -A <host>` first). You'll be prompted for a machine role (`work` / `personal` / `remote`).

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
abbr -a cza 'chezmoi diff; and read -P "apply? " -n1 c; and test "$c" = y; and chezmoi apply'
```

**Edited a `run_once` script that already ran?** It will not re-run — chezmoi tracks
execution in a local state DB. The escape hatch:

```
chezmoi state delete-bucket --bucket=scriptState
```

This bites everyone exactly once.

## Roles

| Role | Gets |
|---|---|
| `work` | Full setup: fish, git, opencode, homebrew, k9s, macOS defaults |
| `personal` | Same as work (identity differs via templates) |
| `remote` | Reduced: fish config, git, opencode, rootless CLI tools. No homebrew, no casks, no macOS defaults. |

## Layout

See [PLAN.md](PLAN.md) for the full design. See [AGENTS.md](AGENTS.md) for agent guidelines.
