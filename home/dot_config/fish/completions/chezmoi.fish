# Chezmoi completion for Fish shell
# Generate completion dynamically if chezmoi is available

if type -q chezmoi
    chezmoi completion fish | source
end
