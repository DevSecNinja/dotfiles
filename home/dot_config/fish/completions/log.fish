# Completion for the `log` dispatcher (wrapper around log.sh)
# See: ~/.config/shell/functions/log.sh

set -l levels trace debug info notice warn error fatal state result hint step banner
set -l seen "not __fish_seen_subcommand_from $levels"

complete -c log -f

# Severities (control filtering)
complete -c log -n "$seen" -a trace  -d 'Severity: detailed tracing (dim)'
complete -c log -n "$seen" -a debug  -d 'Severity: debug info (dim cyan)'
complete -c log -n "$seen" -a info   -d 'Severity: informational'
complete -c log -n "$seen" -a notice -d 'Severity: notice (bold blue)'
complete -c log -n "$seen" -a warn   -d 'Severity: warning -> stderr (bold yellow)'
complete -c log -n "$seen" -a error  -d 'Severity: error -> stderr (bold red)'
complete -c log -n "$seen" -a fatal  -d 'Severity: fatal -> stderr (white on red)'

# Kinds (info-priority categories)
complete -c log -n "$seen" -a state  -d 'Kind: state (cyan)'
complete -c log -n "$seen" -a result -d 'Kind: result (green)'
complete -c log -n "$seen" -a hint   -d 'Kind: hint (magenta)'
complete -c log -n "$seen" -a step   -d 'Kind: step (dim)'
complete -c log -n "$seen" -a banner -d 'Kind: banner'
