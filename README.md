# dotfiles

chezmoi-based dotfiles. Private repo.

## Bootstrap

```sh
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply jakobhavtorn/dotfiles
```

You'll be prompted for a machine role (`work` / `personal` / `remote`).

## Usage

```sh
chezmoi diff     # review pending changes before applying
chezmoi apply    # apply changes
chezmoi update   # git pull + apply
```

**Always diff before apply.** There is no rollback.

If a `run_once` script already ran and you need to re-run it after editing:

```
chezmoi state delete-bucket --bucket=scriptState
```

## Layout

See [PLAN.md](PLAN.md) for the full design.
