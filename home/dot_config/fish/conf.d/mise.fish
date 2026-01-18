# mise (rtx) initialization
# This file handles mise shell integration and completion

# Initialize mise if available
if type -q mise
    mise activate fish | source
end
