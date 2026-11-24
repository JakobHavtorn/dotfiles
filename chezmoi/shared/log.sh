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

# Session log — every log_* call appends one plain-text line to
# $_SESSION_LOG. log_run records its captured output stripped of ANSI/CSI
# sequences and carriage returns, so a plain `cat` of the log is safe;
# log_tee records live output as-is — streaming cannot be filtered without
# changing terminal behavior.
# run_before_00-init-session-log rotates and truncates $_SESSION_LOG at
# apply start, so every line in it belongs to the current apply by
# construction. Line format (a contract — the end-of-apply report reads
# warn/error lines back):
#   HH:MM:SS LEVEL message            levels: section ok info skip warn error
#       <indented output lines>       4-space indent, from log_run/log_tee
# All writes are fail-safe: an unusable $_SESSION_STATE_DIR degrades
# logging to terminal-only; no write path can fail the calling script.
_SESSION_STATE_DIR="$HOME/.local/state/dotfiles"
_SESSION_LOG="$_SESSION_STATE_DIR/last-apply.log"
_SESSION_PREV_LOG="$_SESSION_STATE_DIR/previous-apply.log"

_session_write() {
    # $1 = level, $2 = message. Never fails; never prints to the terminal.
    if [ ! -d "$_SESSION_STATE_DIR" ]; then
        mkdir -p "$_SESSION_STATE_DIR" 2>/dev/null || return 0
    fi
    printf '%s %s %s\n' "$(date +%H:%M:%S)" "$1" "$2" >> "$_SESSION_LOG" 2>/dev/null || true
}

_session_write_output() {
    # $1 = captured command output. The indent keeps these lines from
    # colliding with the LEVEL-line format; the stripping keeps a plain
    # `cat` of the log safe.
    [ -n "$1" ] || return 0
    if [ ! -d "$_SESSION_STATE_DIR" ]; then
        mkdir -p "$_SESSION_STATE_DIR" 2>/dev/null || return 0
    fi
    local _session_line
    printf '%s\n' "$1" | sed -e $'s/\x1b\\[[0-9;?]*[a-zA-Z]//g' -e $'s/\r//g' | while IFS= read -r _session_line; do
        printf '    %s\n' "$_session_line" >> "$_SESSION_LOG" 2>/dev/null || return 0
    done
    # The loop runs in a pipe subshell; without this, a sed failure would
    # surface through the caller's pipefail and break the never-fails
    # contract.
    return 0
}

# Pipe a loud non-interactive command's live output through the session log:
#   brew bundle install --file "$BREWFILE" 2>&1 | log_tee
# pipefail lets the command's exit code propagate through the pipeline;
# the cat fallback keeps an unusable session state dir from failing it.
# Never use this on interactive commands — prompts would land in the log.
log_tee() {
    if mkdir -p "$_SESSION_STATE_DIR" 2>/dev/null && [ -w "$_SESSION_STATE_DIR" ]; then
        _session_write output "(live output follows)"
        tee -a "$_SESSION_LOG"
    else
        cat
    fi
}

log_section() {
    echo ""
    echo -e "${_BOLD}${_BLUE}▶ $1${_RESET}"
    _session_write section "$1"
}

log_ok() {
    echo -e "  ${_GREEN}✓${_RESET} $1"
    _session_write ok "$1"
}

log_warn() {
    echo -e "  ${_YELLOW}⚠${_RESET} $1"
    _session_write warn "$1"
}

log_err() {
    echo -e "  ${_RED}✗${_RESET} $1" >&2
    _session_write error "$1"
}

log_info() {
    echo -e "  ${_DIM}$1${_RESET}"
    _session_write info "$1"
}

log_skip() {
    echo -e "  ${_DIM}⊘ $1${_RESET}"
    _session_write skip "$1"
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
        _session_write_output "$_output"
    else
        log_err "$_label"
        _session_write_output "$_output"
        printf '%s\n' "$_output" >&2
        [[ "$_non_fatal" -eq 1 ]] && return 0
        return 1
    fi
}
