# shellcheck shell=bash
# log.sh — shared logging functions for chezmoi scripts
# Source from other scripts: source "{{ .chezmoi.sourceDir }}/shared/log.sh"

# Colors (only when stdout is a TTY)
if [[ -t 1 ]]; then
    _BOLD='\033[1m'
    _GREEN='\033[0;32m'
    _YELLOW='\033[0;33m'
    _RED='\033[0;31m'
    _BLUE='\033[0;34m'
    _DIM='\033[2m'
    _RESET='\033[0m'
else
    _BOLD='' _GREEN='' _YELLOW='' _RED='' _BLUE='' _DIM='' _RESET=''
fi

# Session log — every log_* call also appends a plain-text line to the file
# below; log_run records its captured output blocks too. The file is the
# apply's record: plain text, no colors, timestamps for correlation.
# Captured output (log_run) is recorded verbatim minus ANSI/CSI sequences
# and carriage returns, so a plain `cat` of the log is safe; log_tee's
# live output is recorded as-is — streaming cannot be filtered without
# changing terminal behavior.
# run_before_00-init-session-log starts each apply — it rotates the previous
# apply's log and truncates, so every line in last-apply.log belongs to the
# current apply by construction. Line format (a contract — the end-of-apply
# report reads warn/error lines back):
#   HH:MM:SS LEVEL message            levels: section ok info skip warn error
#       <indented output lines>       4-space indent, from log_run/log_tee
# All writes are fail-safe: an unusable state dir degrades logging to
# terminal-only and never fails the calling script.
_BS_STATE_DIR="$HOME/.local/state/dotfiles"
_BS_LOG="$_BS_STATE_DIR/last-apply.log"
_BS_PREV="$_BS_STATE_DIR/previous-apply.log"

_bs_write() {
    # $1 = level, $2 = message. Never fails; never prints to the terminal.
    if [ ! -d "$_BS_STATE_DIR" ]; then
        mkdir -p "$_BS_STATE_DIR" 2>/dev/null || return 0
    fi
    printf '%s %s %s\n' "$(date +%H:%M:%S)" "$1" "$2" >> "$_BS_LOG" 2>/dev/null || true
}

_bs_write_output() {
    # $1 = captured command output. Appends it indented so it can never
    # collide with the LEVEL-line format above. ANSI/CSI sequences and
    # carriage returns are stripped first, so a plain `cat` of the log
    # is safe (cursor-control codes must not reach the terminal on
    # readback).
    [ -n "$1" ] || return 0
    if [ ! -d "$_BS_STATE_DIR" ]; then
        mkdir -p "$_BS_STATE_DIR" 2>/dev/null || return 0
    fi
    local _bs_line
    printf '%s\n' "$1" | sed -e $'s/\x1b\\[[0-9;?]*[a-zA-Z]//g' -e $'s/\r//g' | while IFS= read -r _bs_line; do
        printf '    %s\n' "$_bs_line" >> "$_BS_LOG" 2>/dev/null || return 0
    done
    return 0
}

# Pipe a loud non-interactive command's live output through the session log:
#   brew bundle install --file "$BREWFILE" 2>&1 | log_tee
# Streams to the terminal unchanged and appends to the session log; the
# command's exit code still propagates (pipefail). Falls back to cat when
# the state dir is unusable, so logging can never fail the pipeline.
# Never use this on interactive commands (prompts would land in the file).
log_tee() {
    if mkdir -p "$_BS_STATE_DIR" 2>/dev/null && [ -w "$_BS_STATE_DIR" ]; then
        _bs_write output "(live output follows)"
        tee -a "$_BS_LOG"
    else
        cat
    fi
}

log_section() {
    echo ""
    echo -e "${_BOLD}${_BLUE}▶ $1${_RESET}"
    _bs_write section "$1"
}

log_ok() {
    echo -e "  ${_GREEN}✓${_RESET} $1"
    _bs_write ok "$1"
}

log_warn() {
    echo -e "  ${_YELLOW}⚠${_RESET} $1"
    _bs_write warn "$1"
}

log_err() {
    echo -e "  ${_RED}✗${_RESET} $1" >&2
    _bs_write error "$1"
}

log_info() {
    echo -e "  ${_DIM}$1${_RESET}"
    _bs_write info "$1"
}

log_skip() {
    echo -e "  ${_DIM}⊘ $1${_RESET}"
    _bs_write skip "$1"
}

# Run a command, capture its output, and log the result.
#
# Usage: log_run "label" command [args...]
#        log_run --non-fatal "label" command [args...]
#
# On success: logs "✓ label" and returns 0.
# On failure: logs "✗ label", prints captured output to stderr.
#   - Default (fatal): returns 1 — caller should let it propagate under
#     `set -e`, or guard with `if !`/`||` to handle the failure.
#   - With --non-fatal: logs the error and output to stderr but returns
#     0, so the caller continues under `set -e` without `|| true`.
# Captured output is also recorded in the session log on both paths.
log_run() {
    local _label _non_fatal=0
    if [[ "$1" == "--non-fatal" ]]; then
        _non_fatal=1
        shift
    fi
    _label="$1"
    shift
    local _output
    if _output="$("$@" 2>&1)"; then
        log_ok "$_label"
        _bs_write_output "$_output"
    else
        log_err "$_label"
        _bs_write_output "$_output"
        printf '%s\n' "$_output" >&2
        [[ "$_non_fatal" -eq 1 ]] && return 0
        return 1
    fi
}
