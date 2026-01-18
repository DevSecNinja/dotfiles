# GitHub CLI completion for Fish shell
# Generate completion dynamically if gh is available

if type -q gh
    gh completion -s fish | source
end
