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

# Claude Code self-healing wrapper — prepended so it shadows the npm-global
# claude symlink while the auto-updater postinstall bug exists
# (anthropics/claude-code#88091, #86941). Remove with ~/.claude/bin/claude.
fish_add_path $HOME/.claude/bin

# ~/.env — machine-local KEY=value secrets (API keys, MCP tokens), exported
# into every new shell. Blank lines and comments are ignored; any NAME=value
# line is exported, so a new var needs only a line in ~/.env — no per-var
# loader blocks here. (corti-cli may re-add its managed CORTI_* block on
# updates; that is harmless, this loader already covers it.)
if test -f ~/.env
    for env_line in (string match -r '^[A-Za-z_][A-Za-z0-9_]*=.*' < ~/.env)
        set -gx (string split -m 1 = -- $env_line)
    end
end
