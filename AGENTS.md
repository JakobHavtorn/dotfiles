# AGENTS.md

Guidance for AI agents working **on** this repository. Not a skill — no harness loads this file.

## Standards

- All changes merged to `main` via pull request. No direct pushes to `main`.
- Commit titles follow [Conventional Commits](https://www.conventionalcommits.org/).
- Always `chezmoi diff` before `chezmoi apply`. There is no rollback.
- Secrets are never committed. `fish_variables`, `~/.env`, and any file containing tokens/API keys are excluded.

## Layout

```
.chezmoi.toml.tmpl                     # prompts on init (role: work/personal/remote)
.chezmoiignore.tmpl                    # excludes non-chezmoi files + role-specific paths
.chezmoidata.yaml                      # non-secret shared facts for templates
dot_config/                            # maps to ~/.config/
dot_config/fish/                        # fish shell config, functions, conf.d
dot_config/git/config.tmpl              # git global config (insteadOf excluded for remote)
dot_config/opencode/cli.json           # opencode TUI settings (symlinked)
dot_config/opencode/opencode.jsonc     # opencode base config (managed by run_onchange script)
dot_omp/private_agent/private_config.yml  # omp settings (~/.omp/agent/config.yml, 0600; omp rewrites it — `chezmoi re-add` after in-app changes)
dot_omp/private_agent/models.yml       # omp custom providers: corti (key via CORTI_BEARER env)
manifests/                             # readable in git, never written to $HOME
manifests/Brewfile                     # hand-curated homebrew bundle (darwin)
manifests/remote-tools.txt             # pinned release URLs for rootless install (remote/linux)
run_once_before_10-install-homebrew.sh.tmpl   # darwin only
run_onchange_before_15-remote-tools.sh.tmpl   # remote/linux only — installs to ~/.local/bin
run_onchange_after_20-brew-bundle.sh.tmpl      # darwin only
run_onchange_after_20-opencode-config.sh.tmpl  # copies base + corti models init
run_once_after_30-agent-skills.sh              # clones + links agent-skills
scripts/dump.sh                        # weekly dump to manifests/ (macOS, launchd)
.github/workflows/                     # CI
PLAN.md                                # full implementation plan
```

## Conventions

- `run_once_*` — executes exactly once per machine. Guard with `command -v` checks; the prefix is a guard, not idempotency.
- `run_onchange_*` — re-executes when the script's own content changes. Embed manifest hashes as comments to trigger on manifest edits: `# Brewfile hash: {{ include "manifests/Brewfile" | sha256sum }}`
- `before_` / `after_` — relative to file application. The number controls ordering within a phase.
- Script house style: `set -euo pipefail`, a guard clause at the top, echo what it's about to do.
- `uv` owns Python interpreters. Do not `brew install python`.
- The Brewfile is hand-curated, not a raw dump output. `dump.sh` overwrites it, but PR review is the curation gate.
- `remote-tools.txt` is a pipe-delimited manifest: `name|url|path_in_archive`. `path_in_archive` is the relative path to the binary inside the archive, or `-` for direct binary download. Architecture is x86_64; add aarch64 entries when needed.
- Remote role is subtractive: gets fish config, git config, opencode, omp config, agent-skills, and a short list of CLI binaries installed rootless to `~/.local/bin`. Does not get Homebrew, casks, macOS defaults, or k9s.

## Editing run_once scripts

If a `run_once` script already ran and you need to re-run it after editing:

```
chezmoi state delete-bucket --bucket=scriptState
```
