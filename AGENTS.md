# AGENTS.md

Guidance for AI agents working **on** this repository. Not a skill — no harness loads this file.

## Standards

- All changes merged to `main` via pull request. No direct pushes to `main`.
- Commit titles follow [Conventional Commits](https://www.conventionalcommits.org/).
- Always `chezmoi diff` before `chezmoi apply`. There is no rollback.
- Secrets are never committed. `fish_variables`, `~/.env`, and any file containing tokens/API keys are excluded.

## Layout

| Path | Description |
|---|---|
| `.chezmoiroot` | Points to `chezmoi/` — repo root stays clean of chezmoi internals |

**Repo root (not chezmoi-managed):**

| Path | Description |
|---|---|
| `AGENTS.md` | This file — agent guidance for working on the repo |
| `README.md` | User-facing docs |
| `.github/workflows/` | CI |
| `scripts/check-bootstrap.sh` | Platform-agnostic interrupted-apply detector; called from dump.sh and CI |
| `scripts/ci-local.sh` | Local runner for all lint checks: JSON validation, shellcheck, `set -euo pipefail` check, template rendering for both identities. Called by `.pre-commit-config.yaml` and `.github/workflows/lint.yml` — single source of truth |
| `scripts/dump.sh` | Daily dump to manifests/ (macOS, launchd): brew, pipx, omf, macOS defaults, obsidian config. PATH-hardened for launchd |
| `scripts/dump-pr.sh` | Opens a PR for dump.sh manifest changes (macOS, launchd). Closes stale dump PRs first. Called after dump.sh |
| `scripts/seed-github-ssh.sh` | GitHub SSH seeder for fresh machines: keygen at `~/.ssh/id_github`, seed host block + Include line, copy pubkey, open settings/keys, verify `ssh -T`; curl-able pre-clone (public repo) |

**`chezmoi/` — chezmoi source root (via `.chezmoiroot`):**

| Path | Description |
|---|---|
| `chezmoi/.chezmoi.toml.tmpl` | Prompts on init (identity: work/personal); `IDENTITY` env var skips the prompt |
| `chezmoi/.chezmoiignore.tmpl` | Excludes non-home-target files, platform-specific paths (k9s, Library on linux), and identity-scoped files (models.yml off non-work machines) |
| `chezmoi/.chezmoidata.yaml` | Non-secret shared facts (identities, notion deny-list, MCP servers, corti models) — single source of truth for templates |
| `chezmoi/dot_config/` | Maps to `~/.config/` |
| `chezmoi/dot_config/fish/config.fish` | PATH setup, corti-cli env, gpu/oc abbreviations (interactive only) |
| `chezmoi/dot_config/git/ignore` | Global gitignore at ~/.config/git/ignore — git reads it as the default excludes file (see run_onchange_after_10) |
| `chezmoi/dot_config/opencode/cli.json.tmpl` | opencode TUI settings; rendered to `~/.config/opencode/cli.json` by run_onchange_after_20 (not the file mechanism) |
| `chezmoi/dot_config/opencode/tui-preferences.jsonc` | Shared OpenCode TUI plugin preferences; safe to hand-edit — plugins update individual keys and preserve the rest |
| `chezmoi/dot_config/opencode/opencode.jsonc.tmpl` | opencode base config (templated from .chezmoidata; managed by run_onchange script) |
| `chezmoi/dot_config/opencode/plugins/title-gen.ts` | opencode session-title plugin — direct Corti API call per session (title spec from agents/title.md, CORTI_BEARER auth) |
| `chezmoi/dot_pi/agent/mcp.json.tmpl` | Pi MCP server config (templated from .chezmoidata; rendered to `~/.pi/agent/mcp.json` by run_onchange script — Pi itself writes toggles and `pi mcp add` servers into the live file) |
| `chezmoi/dot_pi/agent/extensions/title-gen.ts` | pi session-title extension — same shared title spec and direct Corti API call as the opencode plugin |
| `chezmoi/dot_config/herdr/config.toml.tmpl` | herdr keybindings + linux-only `[terminal] default_shell` (rootless fish via remote-tools.txt) |
| `chezmoi/dot_config/k9s/config.yaml` | Minimal k9s config |
| `chezmoi/private_dot_ssh/config.d/github.tmpl` | github.com SSH host block (UseKeychain only on darwin) |
| `chezmoi/dot_omp/private_agent/private_config.yml.tmpl` | omp settings (templated notion deny-list; `~/.omp/agent/config.yml`, 0600; no trailing newline — omp rewrites the file via `omp config set` and the template must stay byte-identical to its output) |
| `chezmoi/dot_omp/private_agent/models.yml.tmpl` | omp custom providers: corti (key via CORTI_BEARER env; model list from .chezmoidata); work identity only |
| `chezmoi/dot_omp/private_agent/mcp.json.tmpl` | omp MCP servers (templated from .chezmoidata) |
| `chezmoi/dot_omp/private_agent/hooks/post/title-gen.ts` | omp session-title hook — same shared title spec and direct Corti API call as the opencode plugin |
| `chezmoi/dot_config/cortexkit/aft.jsonc` | AFT (CortexKit) config — semantic search backend; shared across opencode + omp |
| `chezmoi/shared/` | Bash helpers sourced by run scripts (not home targets) |
| `chezmoi/shared/log.sh` | Colored logging + session-log tee: log_section, log_ok, log_warn, log_err, log_info, log_skip, log_defer, log_run (--non-fatal), log_tee; every log_* call also appends a plain-text line to the session log — fail-safe |
| `chezmoi/shared/env.sh` | Runtime env helpers: is_ci, is_darwin, is_linux |
| `chezmoi/shared/manifest.sh` | `manifest_each <file> <sep> <callback>` — pipe-delimited manifest iteration |
| `chezmoi/manifests/` | Readable in git, never written to `$HOME` |
| `chezmoi/manifests/Brewfile` | Homebrew bundle (darwin); regenerated by dump.sh, PR review is the curation gate |
| `chezmoi/manifests/remote-tools.txt` | Pinned release URLs for rootless install (remote/linux) |
| `chezmoi/manifests/macos-apps.txt` | Self-updating macOS apps installed from vendor downloads instead of casks (`app_bundle\|url\|bin_in_bundle`) — for apps whose updater takes ownership of the bundle away from the user (Chrome, VS Code, iTerm2, Linear, Notion, Rectangle) |
| `chezmoi/manifests/omf.txt` | OMF packages/themes — dumped from `omf list` (consumed by run_onchange_after_60-omf.sh) |
| `chezmoi/manifests/pipx.txt` | pipx install declaration — dumped from venvs' pipx metadata (package_or_url: git URLs, extras) |
| `chezmoi/manifests/macos-defaults-keys.txt` | Shared (domain\|key\|value) list — read by dump.sh (observes) and run_onchange_after_90-macos-defaults.sh.tmpl (writes) |
| `chezmoi/manifests/macos-defaults.txt` | Observed values for keys in macos-defaults-keys.txt (dumped by dump.sh) |
| `chezmoi/manifests/obsidian/` | Obsidian vault config snapshot — fixed list of vault config files (incl. workspaces.json, saved layouts) + plugin manifests/data (dumped by dump.sh, installed by run_onchange_after_89-obsidian-config.sh.tmpl). Excludes the volatile workspace.json and plugin binaries |
| `chezmoi/manifests/iterm2/` | iTerm2 settings plist under an allowlist — the manifest IS the allowlist: dump.sh refreshes values for tracked keys only, reports new keys for deliberate addition, keeps gone keys' last values; junk classes stripped at bootstrap only; installed by run_after_87-iterm2-config only where no settings exist yet |
| `chezmoi/manifests/karabiner/` | Karabiner-Elements `karabiner.json` — dumped by dump.sh, installed by run_after_87-karabiner-config only where no config exists yet |
| `chezmoi/run_before_00-init-session-log.sh.tmpl` | First script of every apply: rotates the session log (previous apply's last-apply.log → previous-apply.log), truncates, writes the header (date, identity, os, source rev); announces the path |
| `chezmoi/run_once_after_05-ssh-config.sh.tmpl` | Ensures `Include config.d/*` in `~/.ssh/config` (prepends if missing, never rewrites existing content) |
| `chezmoi/run_after_06-seed-github-ssh.sh.tmpl` | Runs on every apply: seeds GitHub SSH via `scripts/seed-github-ssh.sh` on terminal applies (keygen, browser add, `ssh -T` verify); skips in CI/headless or when the key exists; opt out with `SKIP_GITHUB_SSH_SEED` |
| `chezmoi/run_onchange_after_10-git-config.sh.tmpl` | Sets git name/email from `.identity` via `git config --global` (insteadOf skipped in CI) |
| `chezmoi/run_before_09-privileged-preflight.sh.tmpl` | Runs on every apply — root-owned prerequisites (brew prefix; Karabiner-Elements install — its pkg needs root, a brew cask cannot elevate; fish as the login shell — /etc/shells + UserShell are root writes): pure dir-test guards — settled machines never elevate; elevation is mode-matched (admin: sudo via terminal; regular: native administrator dialog via GUI session); non-fatal |
| `chezmoi/run_before_10-install-homebrew.sh.tmpl` | Darwin only — runs on every apply: installs Homebrew interactively when missing; normally unprivileged after 09-preflight prepared the prefix (sudo only as the fallback); headless tries NONINTERACTIVE; non-fatal with recovery commands; opt out with `SKIP_HOMEBREW_INSTALL` |
| `chezmoi/run_onchange_before_15-remote-tools.sh.tmpl` | Linux only — installs to `~/.local/bin` (incl. rootless node + Pi via npm) |
| `chezmoi/run_onchange_after_19-macos-apps.sh.tmpl` | Darwin only — installs apps from macos-apps.txt when missing (DMG or zip; into `/Applications` if writable, else `~/Applications`), links bundled CLIs such as `code` into `~/.local/bin`; never upgrades. Runs before brew bundle so the Brewfile's `vscode` lines find `code`. Skipped in CI |
| `chezmoi/run_onchange_after_20-brew-bundle.sh.tmpl` | Darwin only — installs the Brewfile; resolves brew by direct path (works in the same apply as the install); non-fatal: one failed entry never halts the apply |
| `chezmoi/run_onchange_after_20-opencode-config.sh.tmpl` | Renders opencode.jsonc + cli.json from templates; Corti model wiring lives in 25-corti-models |
| `chezmoi/run_onchange_after_22-pi-config.sh.tmpl` | Renders Pi mcp.json from .chezmoidata (Pi models.json is owned by the corti CLI) |
| `chezmoi/run_onchange_after_25-corti-models.sh.tmpl` | Wires Corti models into opencode + Pi via the corti CLI (npx @corti/cli models init); work identity only |
| `chezmoi/run_after_30-agent-skills.sh.tmpl` | Clones/updates agent-skills, runs skillctl link (every apply — idempotent) |
| `chezmoi/run_onchange_after_60-omf.sh.tmpl` | Installs OMF packages from manifest |
| `chezmoi/run_onchange_after_70-pipx.sh.tmpl` | Installs pipx packages from manifest |
| `chezmoi/run_onchange_after_80-launchd-load.sh.tmpl` | Darwin only — loads dump.sh launchd job |
| `chezmoi/run_onchange_after_80-taxhelper.sh.tmpl` | Installs taxhelper agent skills into ~/.agents/skills (universal agent-skills store); personal identity only |
| `chezmoi/run_onchange_after_81-archify.sh.tmpl` | Installs archify skill (diagrams as HTML) via `npx skills` CLI into ~/.agents/skills |
| `chezmoi/run_onchange_after_85-herdr-plugins.sh.tmpl` | Installs herdr-annotate plugin (Full variant) across opencode, omp, claude, codex, hermes |
| `chezmoi/run_onchange_after_88-hermes-config.sh.tmpl` | Installs/updates Corti Hermes profile distribution from hermes-profile repo; injects CORTI_BEARER, sets corti as sticky default profile |
| `chezmoi/run_after_88-coding-harness-plugin-refresh.sh.tmpl` | Keeps declared harness plugins current every apply: targetless `opencode plugin update` for all configured package plugins, `omp plugin install --force` for @cortexkit/aft-pi (OMP npm plugins have no config surface); pre-warms AFT binary |
| `chezmoi/run_onchange_after_86-obsidian-mcp.sh.tmpl` | Registers the Obsidian Local REST API MCP server with Claude Code (`claude mcp add --scope user`) and Codex (`~/.codex/config.toml`). Reads the API key from the plugin's `data.json` |
| `chezmoi/run_onchange_after_86-handle-mcp.sh.tmpl` | Registers the handle-mcp grocery server (nemlig/BilkaToGo/REMA 1000, personal identity only) with Claude Code and Codex; opencode/OMP/Pi get it from the MCP templates. Removes registrations on work machines |
| `chezmoi/run_after_87-iterm2-config.sh.tmpl` | Darwin only — every apply: installs the iTerm2 settings manifest via `defaults import` when the machine has no iTerm2 settings; existing settings are never overwritten (dump.sh observes them) |
| `chezmoi/run_after_87-karabiner-config.sh.tmpl` | Darwin only — every apply: installs the Karabiner-Elements config manifest when the machine has none; existing config is never overwritten (dump.sh observes it) |
| `chezmoi/run_onchange_after_89-obsidian-config.sh.tmpl` | Darwin only — copies Obsidian vault config from manifests/obsidian/ into the live vault (excludes workspace state + plugin binaries) |
| `chezmoi/run_onchange_after_90-macos-defaults.sh.tmpl` | Darwin only — sets the shared defaults keys; per-key non-fatal (re-runs when the keys file changes) |
| `chezmoi/run_after_95-vscode-default-app.sh.tmpl` | Darwin only — every apply: sets VS Code as default for dev file types via duti (typed extensions) plus an LSHandlers fallback (UTI-less extensions, one atomic merge-write); non-fatal without duti (arrives with brew bundle) |
| `chezmoi/run_after_98-layer-defers.sh.tmpl` | Every apply, probes each layer's machine-state preconditions; a missing one records log_defer with its fix hint; silent when clean; the probe home — new layers add probes here, the report never changes |
| `chezmoi/run_after_99-bootstrap-report.sh.tmpl` | End-of-run report: replays warn/error/defer lines from the session log and prints the log path; pure presentation — no machine probing; quiet when clean; complements scripts/check-bootstrap.sh (interrupted-apply detection) |
| `chezmoi/Library/LaunchAgents/` | launchd plist for daily dump.sh + dump-pr.sh (no `dot_` prefix — Library is not hidden) |

## Conventions

- Two config management strategies. Authored configs (fish, herdr, k9s, SSH, git, omp, LaunchAgents plists) live as chezmoi source files in `dot_config/`, `dot_omp/`, `Library/`. You write them, chezmoi applies them. Observed state from external tools (Brewfile, pipx.txt, omf.txt, macOS defaults, Obsidian vault config) lives in `manifests/`. `dump.sh` captures it daily, PR review is the curation gate, `run_onchange` scripts install it. The split: if you hand-write it, it is a source file; if a tool generates it, it is a manifest.
- Some authored configs live in their own repos rather than as chezmoi source files. The Hermes profile distribution is one example: it has a native install mechanism (`hermes profile install github.com/...`) that expects a standalone git repo, so the dotfiles repo invokes it via `run_onchange_after_88-hermes-config.sh.tmpl` without containing the content. This mirrors how the Brewfile and pipx.txt reference packages by name or URL rather than inlining them — the dotfiles repo holds references, not the packages themselves. Obsidian config, by contrast, has no equivalent distribution mechanism, so it lives as a manifest in `manifests/obsidian/` and is installed by a copy script.

- `run_once_*` — executes exactly once per machine. Guard with `command -v` checks; the prefix is a guard, not idempotency.
- `run_after_*` / `run_before_*` (no `once`/`onchange`) — executes on every `chezmoi apply`. Use for idempotent operations that must track upstream changes (e.g. agent-skills: sync clone to `origin/main` + `skillctl link`). The script itself must be safe to re-run.
- `run_onchange_*` — re-executes when the script's own content changes. Embed manifest hashes as comments to trigger on manifest edits: `# Brewfile hash: {{ include "manifests/Brewfile" | sha256sum }}`
- `before_` / `after_` — relative to file application. The number controls ordering within a phase.

### Run-script trigger policy

- Trigger choice follows where the decision's state lives: `run_onchange_*` + an embedded input hash when the repo input is authoritative and the layer is expensive to re-run (brew bundle, OMF, pipx); `run_after_*` + guard when machine state decides — the guard tests reality at execution time, so recovery flows ("delete the file and re-apply") always work. Presence facts are the price of keeping an expensive machine-state layer on `run_onchange_*`; never pay it for a cheap layer.
- `run_before_*`/`run_after_*` (no once/onchange) — every apply. Use for interactive or precondition-dependent steps; guard-first and idempotent, so a settled machine pays only a guard test. Opt-outs: `SKIP_HOMEBREW_INSTALL`, `SKIP_GITHUB_SSH_SEED`.
- `run_onchange_*` — embed a presence fact for every installable precondition, so a guard-skip cannot permanently silence the layer: `#   brew: {{ output "sh" "-c" "<probe>" | trim }}` (copy the exact form from any `run_onchange_*` header). The probe must find the tool without the shell's PATH — chezmoi renders facts in its own environment. When the fact flips, the rendered hash changes and the script re-runs.
- `run_once_*` — only when nothing can defer (`run_once_after_05-ssh-config`).
- Root-requiring one-time setup belongs in `run_before_09-privileged-preflight` — add a cheap unprivileged guard to its collect block and a `case` arm that fixes it with one batched root command. Prerequisites must be one-shot and idempotent; recurring privilege needs get designed away instead (see the cask `appdir` pattern).
- `run_after_99-bootstrap-report` replays the session log's warn/error/defer lines at the end of every apply; `scripts/check-bootstrap.sh` still detects interrupted applies via the state DB.
- log_defer vs log_skip: skip is routine (nothing to do), defer is unfinished (a layer could not run). Machine-state deferrals are probed by `run_after_98-layer-defers` every apply; layer scripts log_defer only for deferrals the probes cannot see; a layer that runs and fails records warn/error instead.
- The bootstrap may restart only jobs it owns (the launchd dump job). Harness services and other user processes get told, not killed: restart guidance lives in defer hints and the README — the user picks the moment.
- Script house style: `set -euo pipefail`, a guard clause at the top, echo what it's about to do.
- Shared helpers (`shared/`): `log.sh` for colored logging, `env.sh` for runtime checks (`is_ci`, `is_darwin`, `is_linux`), `manifest.sh` for `manifest_each`. Source these instead of reimplementing the same capture/loop/gate patterns. `log_run "label" cmd…` replaces inline `output="$()"` capture-and-log; `log_run --non-fatal` logs the error but returns 0 (no `|| true` needed under `set -e`).
- Session log: every `log_*` call tees a plain-text line to `~/.local/state/dotfiles/last-apply.log`; `run_before_00` rotates it at apply start; loud non-interactive commands stream through `log_tee`; `log_run` output is recorded automatically.
- corti models init (opencode config script) and agent-skills are optional personal-layer steps: a missing-auth failure there is logged non-fatally and must never abort the rest of the bootstrap — catch the failure, print the tool's own error, exit 0. Platform/resource guards (`command -v`, os checks) handle the rest.
- `uv` owns Python interpreters. Do not `brew install python`.
- The Brewfile is hand-curated, not a raw dump output. `dump.sh` overwrites it, but PR review is the curation gate. Cask `args: { appdir: "~/Applications" }` entries (non-admin support) are part of that curation — `brew bundle dump` strips them; re-add on review. Same gate applies to all dump-generated manifests; pipx.txt is dumped from the venvs' pipx metadata (`package_or_url`) so install sources survive regeneration.
- `remote-tools.txt` is a pipe-delimited manifest: `name|url|path_in_archive`. `path_in_archive` is the relative path to the binary inside the archive, or `-` for direct binary download. Architecture is x86_64; add aarch64 entries when needed.
- Linux is subtractive: gets fish (via remote-tools.txt) + fish config, git config, opencode, omp config, agent-skills, and a short list of CLI binaries installed rootless to `~/.local/bin`. Does not get Homebrew, casks, macOS defaults, or k9s. Herdr's `default_shell` is set to the rootless fish binary since `chsh` is unavailable. Platform is detected from `.chezmoi.os`, not from a role datum.

## Editing run_once scripts

If a `run_once` script already ran and you need to re-run it after editing:

```
chezmoi state delete-bucket --bucket=scriptState
```
