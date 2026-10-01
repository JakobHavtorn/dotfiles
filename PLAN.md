# Dotfiles: implementation plan

A chezmoi-based setup for reproducing a development environment from a single command.
Primary target is macOS; remote Linux boxes get a deliberately reduced profile (§3.1).
Private repo, incremental rollout, working machine at every step.

Bootstrap target:

```
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply jakobhavtorn/dotfiles
```

---

## 1. Decisions

Fixed up front so they don't get relitigated mid-build.

| Question | Decision | Why |
|---|---|---|
| Repo visibility | **Private** | Accumulates kube contexts, Azure tenant/subscription IDs, internal hostnames, SSH aliases. Not secret, but free reconnaissance. |
| Entrypoint | chezmoi only | Two entrypoints means one silently rots. `chezmoi apply` gets run regularly; a `bootstrap.sh` would not. |
| Work/personal split | **Config layer only** | Same tools everywhere; an unused `az` on the personal Mac costs nothing. Identity and infrastructure pointers do differ. See §3. |
| Remote SSH boxes | **Third role, subtractive** | Not a second OS to reach parity with. Rootless, minimal, no casks. See §3.1. |
| macOS package layer | homebrew, full stop | `brew bundle dump` already captures nearly everything. One manifest, one mechanism. |
| Remote package layer | **Deferred** | Not Linuxbrew. Mechanism chosen once the tool list exists (§3.1, open item). |
| Python interpreters | **uv** | `uv python install`. Nothing else installs Pythons — not brew, not the system. |
| poetry / pipx | Keep, unchanged | They stay in the Brewfile. Migrating project repos off them is a separate concern that doesn't belong here. |
| Per-project deps | project tooling / devcontainers | Not this repo's job. |
| Secrets | **None in v1** | Deferred until the boring parts work (§6). |

**The plan is deliberately tool-agnostic below the manifest layer.** It fixes *where*
things are declared and *who owns which category*, not which binaries you happen to
want. Adding Go, or dropping a tool, should be a one-line manifest edit, never a
structural change.

**The one rule that matters:** uv owns Python interpreters. Do not `brew install python`,
do not rely on the system python. Everything else on macOS is brew's.

---

## 2. Repo layout

```
dotfiles/                              (private)
├── README.md
├── PLAN.md                            ← this file
├── .chezmoiignore.tmpl                # templated: excludes Mac-only tree when remote
├── .chezmoidata.yaml                  # non-secret shared facts
├── .chezmoi.toml.tmpl                 # prompts on init, CI-safe defaults
│
├── dot_config/
│   ├── fish/
│   │   ├── config.fish
│   │   ├── conf.d/
│   │   └── functions/
│   ├── git/config.tmpl
│   └── k9s/
│
├── manifests/                         # readable in git, never written to $HOME
│   ├── Brewfile                       # hand-curated, not raw dump output
│   ├── fisher.txt
│   ├── pipx.txt
│   └── remote-tools.txt               # TBD — see §3.1
│
├── run_once_before_10-install-homebrew.sh.tmpl     # darwin only
├── run_onchange_after_20-brew-bundle.sh.tmpl       # darwin only
├── run_onchange_after_50-remote-tools.sh.tmpl      # remote only
├── run_onchange_after_60-fisher.sh.tmpl            # darwin only
├── run_once_after_90-macos-defaults.sh.tmpl        # darwin only
│
├── scripts/
│   └── dump.sh
│
└── .github/workflows/
    ├── lint.yml                       # every push, ubuntu, seconds
    ├── clean-install-linux.yml        # every push, ubuntu container, cheap + honest
    └── clean-install-macos.yml        # weekly cron, macos, expensive + partial
```

Notes:

- No `.chezmoiroot` / `home/` indirection. It exists to let a repo host non-chezmoi
  content at top level; there are two such directories here, and `.chezmoiignore`
  covers them.
- Scripts reference manifests by absolute path via `{{ .chezmoi.sourceDir }}`.
- The script numbering leaves gaps on purpose. Inserting a step shouldn't mean renaming
  files, because renaming a `run_once` file makes chezmoi treat it as new.

### Script naming

The prefixes are load-bearing:

- `run_once_*` — executes exactly once per machine, tracked in chezmoi's local state DB.
- `run_onchange_*` — re-executes when the script's own content changes. To trigger on
  manifest edits, embed the manifest's hash in a comment:
  `# Brewfile hash: {{ include "manifests/Brewfile" | sha256sum }}`
- `before_` / `after_` — relative to file application.
- The number controls ordering within a phase.

---

## 3. Machine identity

`.chezmoi.toml.tmpl` prompts once on init and persists the answer:

```
{{- $role := promptStringOnce . "role" "Machine role (work/personal/remote)" -}}
[data]
    role = {{ $role | quote }}
```

CI passes `--promptString role=personal` (macOS job) or `role=remote` (Linux job) so it
never blocks.

**One axis, three values.** `work` / `personal` / `remote`. Resist adding a separate
`.chezmoi.os` dimension — os × role is four combinations to reason about and test, and
`remote` already implies Linux for your purposes. If a Linux desktop ever appears,
revisit then.

**The work/personal split is config-layer only.** One Brewfile, installed on both Macs.
What actually diverges is identity and infrastructure pointers: git email, SSH host
aliases, kube contexts, Azure defaults.

**Template per file, not per repo.** Templating is the main thing that makes chezmoi
harder to debug than plain symlinks, so keep the blast radius small: plain
`config.fish`, plus a single `conf.d/work.fish.tmpl` that renders empty when `.role`
isn't `work`. Most of the repo stays untemplated. Divergence lives in two or three files
you can point at.

**Don't template anything in Phase 1.** The `role` prompt costs one question at init and
nothing else, so it goes in early and sits unused. Phase 2 is when real configs move
across and the actual divergences become visible — decide then, with evidence.

**Git email may not need chezmoi at all.** If that's the only thing that differs, `git`'s
own `includeIf gitdir:` directive handles it from one committed config, keyed on which
directory tree the repo lives in. No templating, no role branch.

Keeping `role` also means work-specific content is one `grep` away should a public subset
ever be wanted.

### 3.1 The remote profile

Remote is **subtractive, not a port**. Don't try to make a shared training box look like
the laptop — that's where this gets unpleasant.

**Gets:** fish config, git config, fish functions and abbreviations, uv, and a short list
of CLI binaries. Everything rootless under `~/.local`.

**Doesn't get:** Brewfile, macOS defaults, casks, GUI anything, fisher plugins that shell
out to Mac-only tools, 1Password integration.

**`.chezmoiignore.tmpl` does the heavy lifting.** Exclude the Mac-only tree wholesale
rather than scattering `{{ if }}` through individual files:

```
{{ if eq .role "remote" }}
.config/k9s
Library/
{{ end }}
```

**The package mechanism is deliberately unspecified.** It depends on the tool list, which
doesn't exist yet. Whatever it ends up being, it must be rootless, install to
`~/.local/bin`, and be declared in `manifests/remote-tools.txt` rather than embedded in
the script. Likely a short curl-and-extract loop over pinned release URLs; that's fine
for a handful of tools and has no moving parts.

**Python on remote is uv,** same as macOS. Single static binary, rootless, no exceptions.

**Two things that bite on shared boxes:**

- **Fish may not be installed, and you may not be able to install it system-wide.** A
  fish not in `/etc/shells` can't be the login shell — you end up with `exec fish` from
  `.bashrc`. Workable, but decide deliberately (open item, §11), and see §9 for the
  duplicate-append trap.
- **Shared `$HOME` conventions, sometimes shared accounts.** If any of these boxes are
  multi-user or managed by someone else, check before rewriting `~/.config` on them.

chezmoi's own bootstrap is fine here: the static binary installs to `~/.local/bin`
without root, so the one-liner works unchanged.

---

## 4. CI

Split honestly: cheap checks prove what they can, expensive checks are acknowledged as
imperfect.

### `lint.yml` — ubuntu, every push

- `shellcheck` on every `run_*` and `scripts/*.sh`
- `chezmoi execute-template` over every `.tmpl` for **all three roles**
- `grep` assertion that every `run_*` script sets `set -euo pipefail` (§9)

The second one is the valuable half: it catches template errors at commit time rather
than on a broken laptop at 11pm.

### `clean-install-linux.yml` — ubuntu container, every push

Full `chezmoi init --apply --promptString role=remote` in a bare container, asserting
exit 0 and that the expected binaries land in `~/.local/bin`.

**This is the honest one.** A clean container really is a clean machine: nothing
preinstalled, no root assumed, so the rootless path handling gets genuinely exercised.
Cheap enough to run on every push.

**Run `chezmoi apply` a second time and assert exit 0.** Free here, and it's the only
automated test of §9's idempotency requirements you'll get.

### `clean-install-macos.yml` — macos-latest, weekly cron + manual dispatch

Full `chezmoi init --apply`, asserting exit 0 and `fish -c 'echo ok'`.

**What this does not prove:** GitHub's macOS runners ship with homebrew and a large
preinstalled toolchain, so the homebrew install script never exercises its real path and
`brew bundle install` partly no-ops. It's a smoke test. Treat it as such. It is also
billed at 10× the Linux rate on private repos — hence weekly, not per-push.

Genuine proof of a clean macOS install is the next time a Mac actually gets set up.
Expect one or two things to be wrong then regardless.

---

## 5. `dump.sh`

Runs weekly via launchd on the Mac. **macOS only** — remote boxes have nothing to
discover, since their tool list is declared rather than dumped. Writes manifests and
**stops**.

```bash
#!/usr/bin/env bash
set -euo pipefail

cd "$(chezmoi source-path)"

brew bundle dump --force --file manifests/Brewfile
fish -c 'omf list'        | parse  > manifests/omf.txt        # plugin|name / theme|name
go version -m \$gobin/\$bin | parse     > manifests/go-tools.txt        # package@version
npm ls -g --depth=0 --json | parse  > manifests/npm-globals.txt    # name@version
awk declared keys; defaults read ?  > manifests/macos-defaults.txt  # domain key = value
```

Generated files are **observed state**. Anatomy of the split:

| Manifest | Role | Dumped? |
|---|---|---|
| `Brewfile` | observed, curation gate in review | yes |
| `omf.txt` | install declaration, observed state converges to it | yes |
| `go-tools.txt`, `npm-globals.txt`, `macos-defaults.txt` | observed only (no consumer script yet) | yes |
| `pipx.txt` | install declaration, dumped from the venvs' pipx metadata (curation gate in review) | yes |
| `remote-tools.txt` | install declaration | **no** — dumping would resurrect deliberately-removed packages and reinstall them next apply |

`dump.sh` is PATH-hardened (launchd ships `/usr/bin:/bin` only) and runs under macOS `/bin/bash` 3.2 — keep it free of bash 4+ constructs (`mapfile`, associative arrays).

Manual System Settings edits outside the declared defaults keys are not captured —
the declared key list in `run_once_after_90` is the boundary. Extend the script
before the dump can see the value.

**No auto-commit.** An unattended job that commits whatever is on the machine is exactly
the mechanism by which a token ends up in git history — and it produces constant diff
noise from brew reordering. A dirty tree is visible next time you `cd` in. Review,
curate, commit by hand.

**First dump:** the output will include things installed once to try and forgotten, plus
transitive dependencies. Curate properly once; it stays clean after that.

---

## 6. Secrets — deferred, and why

Templating a token from 1Password creates a bootstrap ordering problem: `chezmoi init
--apply` fails at the templating step on a fresh machine because the `op` CLI isn't
installed or signed in yet. The one-command bootstrap quietly becomes a three-step dance.

Solvable (a `run_once_before` that installs and prompts for sign-in; or
`--exclude=encrypted` on first pass), but it's not worth solving before the boring parts
work. Add in a later phase if actually needed.

---

## 7. Phases

Each phase leaves a working machine. Nothing is "migrate everything, then flip the switch".

**Phase 1 — fish only.** *One evening.*
Private repo, `chezmoi init`, `chezmoi add ~/.config/fish`, apply, confirm a new shell
works. Add the `role` prompt but template nothing. Outcome: version-controlled shell
config, nothing lost.

**Phase 2 — remaining configs.** *One evening.*
git, k9s, gh. Note what genuinely differs between machines as you move each one across,
then template only those files (§3). Still no scripts. Add `lint.yml`.

**Phase 3 — macOS packages.** *One evening.*
Curate `Brewfile` by hand from a dump. Add the homebrew install and brew bundle scripts.
**The one-line bootstrap becomes real here.**

**Phase 4 — remote role.** *One evening, once the tool list exists.*
Add `remote` to the role prompt, write `.chezmoiignore.tmpl`, decide the install
mechanism, declare the tools in `manifests/remote-tools.txt`. Test against one box you
don't mind breaking before touching the rest. Add `clean-install-linux.yml` — this is
the phase where CI starts proving something real.

**Phase 5 — polish.** *Whenever.*
`dump.sh` + launchd, macOS defaults, `clean-install-macos.yml`.

---

## 8. Nix decision point

Phases 1–2 are dotfiles in git with templating. **That work is not wasted if this goes
Nix later** — many people run home-manager for packages and keep chezmoi for dotfiles,
because home-manager's file management is clumsier for config you edit often.

So the real fork is **Phase 3**, the package layer. Reach it, then decide.

Switch to nix-darwin if any of these are true by then:

1. Rollback matters. `darwin-rebuild switch --rollback` is the one property chezmoi has
   no answer for.
2. Reproducible per-project dev shells matter more than a tidy laptop — `nix develop`
   beats devcontainers on speed and avoids the macOS filesystem tax.
3. The learning appeals on its own terms.

Costs that remain real: the Nix language, flakes nominally experimental, home-manager
option churn between releases, hostile error messages, and Python packaging in nixpkgs
(workaround: `uv` inside a nix shell — works, but that's two systems).

One more consideration now that remote is in scope: home-manager works on Linux and
would unify macOS and remote under one system, which is a genuine point in its favour.
But it wants a Nix daemon installed on every box — a harder sell on shared or managed
infrastructure than a static binary in `~/.local/bin`.

---

## 9. Idempotency and convergence

Every script must be safe to run twice. The point isn't elegance — it's that a setup you
can re-run is a setup you *do* re-run, weekly rather than once every three years, which
is the only thing that keeps it honest.

### Already idempotent

| | Note |
|---|---|
| `chezmoi apply` | Declarative. Also **destructive**: silently overwrites a config a tool rewrote in place. This is what `chezmoi diff` is for. |
| `brew bundle install` | Skips what's present. |
| `uv python install` | No-ops if the version exists. |
| `defaults write` | Sets a value, not an increment. |
| `dump.sh` | Overwrites manifests wholesale. |

### Requirements on scripts that aren't

**`run_once` is a guard, not idempotency.** When a script fails partway, chezmoi doesn't
mark it as run — so the retry executes against a half-finished state. Every script needs
its own guard regardless of prefix.

- **Homebrew install** — the official installer errors if brew is already present. Guard:
  `command -v brew >/dev/null && exit 0` before the curl.
- **Remote tool install** — check the pinned version before downloading; extract to a
  temp path and `mv` into place so a failed download can't leave a truncated binary on
  `$PATH`.
- **`exec fish` in `.bashrc`** — the classic duplicate-append bug. Use a marker block and
  `grep -q` for it, or let chezmoi own the whole file.
- **`chsh`** — succeeds once, errors after. Guard on `$SHELL` already matching.

House style for every `run_*` script: `set -euo pipefail`, a guard clause at the top,
and an echo of what it's about to do so a failure tells you where you are.

### The gap: idempotent is not convergent

Everything here is **additive**. Delete a line from the Brewfile and nothing uninstalls.
Remove a fisher plugin and it stays. After two years the machine is a superset of the
manifest, and a fresh install produces a *different* machine than the one you dumped
from — precisely the drift this repo exists to prevent.

Mitigations, in order of cost:

1. **Visibility.** Have `dump.sh` also run `brew bundle cleanup --file manifests/Brewfile`
   (dry run by default) so the accumulation is in front of you weekly.
2. **Deliberate pruning.** `brew bundle cleanup --force` as an occasional conscious chore.
   Destructive, so never unattended, never in a `run_*` script.
3. **Accept it.** For a laptop, a superset is rarely harmful. Just don't mistake it for
   reproducibility.

Convergence is free under Nix. This is the sharpest remaining argument for §8, and the
honest reason the plan's "reproducible" claim is really "reproducible enough".

---

## 10. Operational habits

Two things that belong in the README, not just in someone's head.

**Always diff before apply.** There is no rollback and no transaction — a failure on
file 40 of 60 leaves the first 39 written. The diff is the safety net.

```fish
abbr -a cza 'chezmoi diff; and read -P "apply? " -n1 c; and test "$c" = y; and chezmoi apply'
```

**Edited a `run_once` script that already ran?** It will not re-run. The escape hatch:

```
chezmoi state delete-bucket --bucket=scriptState
```

This bites everyone exactly once. Write it down now.

---

## 11. Open items

- [ ] Curate `Brewfile` from current machine state — the only macOS step with unknown scope
- [ ] Phase 2: list what actually differs between the two Macs. If it's only git email,
      use `includeIf gitdir:` and leave `.role` unused (§3)
- [ ] Remote: write the tool list. Start minimal and add on demand rather than porting
      the Brewfile
- [ ] Remote: pick the install mechanism once the list exists (§3.1)
- [ ] Remote: assume fish, or degrade to bash? If fish, decide between `chsh` (needs
      `/etc/shells` and possibly an admin) and `exec fish` from `.bashrc`
- [ ] Remote: which boxes are multi-user or centrally managed? Check before applying
- [ ] macOS defaults: worth automating, or a once-per-three-years manual chore?
- [ ] Any non-Python runtimes worth pinning (Go, Node)? Currently assumed brew-installed
      and unversioned
- [ ] Decide the `brew bundle cleanup` cadence — quarterly chore, or accept the superset
      and stop calling it reproducible (§9)
