#!/usr/bin/env bash
# window_agent_state.sh — Outputs a colored ANSI indicator for the
# highest-priority agent state across all panes in a window, or nothing
# if no agent state is tracked by tmux-agent-indicator.
#
# Args:
#   $1 = window target (e.g. "work:1")
#
# Output:
#   " <colored symbol>" (with a leading space), or empty string

WINDOW_TARGET="$1"

RED=$'\033[31m'
YELLOW=$'\033[33m'
GREEN=$'\033[32m'
RESET=$'\033[0m'

# Returns numeric priority for a state (higher = more urgent)
priority_of() {
    case "$1" in
        needs-input) echo 2 ;;
        running)     echo 1 ;;
        done)        echo 0 ;;
        *)           echo -1 ;;
    esac
}

best_state=""
best_priority=-1

while IFS= read -r pane_id; do
    [[ -z "$pane_id" ]] && continue
    state=$(tmux show-environment -g "TMUX_AGENT_PANE_${pane_id}_STATE" 2>/dev/null | cut -d= -f2-)
    [[ -z "$state" ]] && continue
    p=$(priority_of "$state")
    if (( p > best_priority )); then
        best_priority=$p
        best_state=$state
    fi
done < <(tmux list-panes -t "$WINDOW_TARGET" -F '#{pane_id}' 2>/dev/null)

case "$best_state" in
    needs-input) printf " %s!%s" "$RED" "$RESET" ;;
    running)     printf " %s…%s" "$YELLOW" "$RESET" ;;
    done)        printf " %s✓%s" "$GREEN" "$RESET" ;;
esac
