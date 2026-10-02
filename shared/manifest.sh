# shellcheck shell=bash
# manifest.sh — manifest iteration helper for chezmoi scripts
# Source from other scripts: source "{{ .chezmoi.sourceDir }}/shared/manifest.sh"

# Iterate over a pipe-delimited manifest file, calling a callback for each
# non-comment, non-empty line.
#
# Usage: manifest_each <file> <separator> <callback_function_name>
#
# The callback receives the fields as positional args (IFS field-split on
# the separator). Comment lines (starting with optional whitespace then #)
# and empty/whitespace-only lines are skipped.
#
# Example:
#   my_cb() { echo "name=$1 url=$2"; }
#   manifest_each "$MANIFEST" "|" my_cb
#
# Works in bash 3.2 (no mapfile, no associative arrays).
manifest_each() {
    local _file="$1"
    local _sep="$2"
    local _callback="$3"
    local _line _trimmed
    while IFS= read -r _line || [[ -n "$_line" ]]; do
        # Strip leading whitespace for comment detection
        _trimmed="${_line#"${_line%%[![:space:]]*}"}"
        # Skip comments and empty lines
        [[ -z "$_trimmed" || "$_trimmed" == \#* ]] && continue
        # Field-split on the separator and call the callback
        local IFS="$_sep"
        # shellcheck disable=SC2086
        "$_callback" $_line
    done < "$_file"
}
