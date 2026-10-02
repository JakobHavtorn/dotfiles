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

log_section() {
    echo ""
    echo -e "${_BOLD}${_BLUE}▶ $1${_RESET}"
}

log_ok() {
    echo -e "  ${_GREEN}✓${_RESET} $1"
}

log_warn() {
    echo -e "  ${_YELLOW}⚠${_RESET} $1"
}

log_err() {
    echo -e "  ${_RED}✗${_RESET} $1" >&2
}

log_info() {
    echo -e "  ${_DIM}$1${_RESET}"
}

log_skip() {
    echo -e "  ${_DIM}⊘ $1${_RESET}"
}

# Run a command, capture its output, and log the result.
#
# Usage: log_run "label" command [args...]
#        log_run --non-fatal "label" command [args...]
#
# On success: logs "✓ label" and returns 0.
# On failure: logs "✗ label", prints captured output to stderr.
#   - Default (fatal): returns 1 — caller should let it propagate under
#     `set -e`, or guard with `|| true` to continue.
#   - With --non-fatal: returns 1 but callers typically use `|| true`
#     to swallow the exit code so `set -e` does not fire.
log_run() {
    local _label
    # --non-fatal is a documentation marker: callers use `|| true` to
    # continue under set -e. The return value is the same either way.
    if [[ "$1" == "--non-fatal" ]]; then
        shift
    fi
    _label="$1"
    shift
    local _output
    if _output="$("$@" 2>&1)"; then
        log_ok "$_label"
    else
        log_err "$_label"
        printf '%s\n' "$_output" >&2
        return 1
    fi
}
