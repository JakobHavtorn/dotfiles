if status is-interactive
    # Azure Arc GPU SSH — resource-group stated once; gpu1..gpu4 expand to gpu00N
    for i in 1 2 3 4
        abbr --position command gpu$i "az ssh arc --resource-group cph-datacenter-arc-gpu --vm-name gpu00$i"
    end

    abbr -a oc opencode
end

set PATH $PATH $HOME/.local/bin

# Export go path (skip when go is not installed)
if command -v go >/dev/null
    set PATH $PATH:$(go env GOPATH)/bin
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
