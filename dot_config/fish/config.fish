if status is-interactive
    # Commands to run in interactive sessions can go here
end

# Created by `pipx` on 2024-12-09 10:59:26
set PATH $PATH $HOME/.local/bin

# Export go path (skip when go is not installed)
if command -v go >/dev/null
    set PATH $PATH:$(go env GOPATH)/bin
end

pyenv init - | source
# >>> corti-cli >>>
# managed by corti-cli - safe to remove; loads CORTI_* from ~/.env into new shells
if test -f ~/.env
    for corti_line in (string match -r '^CORTI_[A-Za-z0-9_]*=.*' < ~/.env)
        set -gx (string split -m 1 = -- $corti_line)
    end
end
# <<< corti-cli <<<

