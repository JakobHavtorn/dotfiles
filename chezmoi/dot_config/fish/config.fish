if status is-interactive
    # Azure Arc GPU SSH — resource-group stated once; gpu1..gpu4 expand to gpu00N
    for i in 1 2 3 4
        abbr --position command gpu$i "az ssh arc --resource-group cph-datacenter-arc-gpu --vm-name gpu00$i"
    end

    abbr -a oc opencode
end

set PATH $PATH $HOME/.local/bin

# Homebrew — prepend so brew tools shadow system ones (macOS only;
# fish_add_path skips dirs that do not exist, so this is inert on Linux)
fish_add_path /opt/homebrew/bin /opt/homebrew/sbin

# Export go path (skip when go is not installed)
if command -v go >/dev/null
    fish_add_path (go env GOPATH)/bin
end

# >>> corti-cli >>>
# managed by corti-cli - safe to remove; loads CORTI_* from ~/.env into new shells
if test -f ~/.env
    for corti_line in (string match -r '^CORTI_[A-Za-z0-9_]*=.*' < ~/.env)
        set -gx (string split -m 1 = -- $corti_line)
    end
end
# <<< corti-cli <<<

# >>> obsidian-mcp >>>
# loads OBSIDIAN_LOCAL_REST_MCP_TOKEN from ~/.env into new shells (for OMP MCP config)
if test -f ~/.env
    for obs_line in (string match -r '^OBSIDIAN_LOCAL_REST_MCP_TOKEN=.*' < ~/.env)
        set -gx (string split -m 1 = -- $obs_line)
    end
end
# <<< obsidian-mcp <<<

# >>> slack-mcp >>>
# loads SLACK_CLIENT_ID / SLACK_CLIENT_SECRET from ~/.env into new shells.
# Slack MCP is DCR-less: the opencode/omp/pi MCP configs pass these to
# mcp.slack.com as the pre-registered OAuth client. ~/.env is the single
# source of truth; never hardcode credentials here or in fish_variables.
if test -f ~/.env
    for slack_line in (string match -r '^SLACK_CLIENT_(ID|SECRET)=.*' < ~/.env)
        set -gx (string split -m 1 = -- $slack_line)
    end
end
# <<< slack-mcp <<<
