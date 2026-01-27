# Task (go-task) initialization and completion
# https://taskfile.dev

# Load Task completion if Task is available
if type -q task
    task --completion fish | source
end
