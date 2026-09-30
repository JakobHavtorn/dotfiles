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
