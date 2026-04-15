#!/usr/bin/env bats
# Tests for scripts/window_agent_state.sh
# Run with: bats tests/window_agent_state.bats
#
# The script is tested as a pure function:
#   - BATS_PANE_STATES controls mock pane list and per-pane state
#     Format: one "pane_id state" entry per line, e.g. "%0 running"
#   - Assert the colored ANSI suffix written to stdout

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/window_agent_state.sh"

# Expected ANSI indicator values
RED=$'\033[31m'
YELLOW=$'\033[33m'
GREEN=$'\033[32m'
RESET=$'\033[0m'

RUNNING_INDICATOR=" ${YELLOW}…${RESET}"
NEEDS_INPUT_INDICATOR=" ${RED}!${RESET}"
DONE_INDICATOR=" ${GREEN}✓${RESET}"

# Mock tmux:
#   list-panes  → prints first field (pane_id) of each BATS_PANE_STATES line
#   show-environment → looks up state for the requested pane_id
tmux() {
    case "$*" in
        *"list-panes"*)
            echo "$BATS_PANE_STATES" | awk 'NF{print $1}'
            ;;
        *"show-environment"*)
            local varname="${@: -1}"
            local pane_id="${varname#TMUX_AGENT_PANE_}"
            pane_id="${pane_id%_STATE}"
            local state
            state=$(echo "$BATS_PANE_STATES" | awk -v p="$pane_id" '$1==p{print $2}')
            [[ -n "$state" ]] && echo "${varname}=${state}"
            ;;
    esac
}
export -f tmux

# ---------------------------------------------------------------------------
# Single pane — each state
# ---------------------------------------------------------------------------

@test "single pane running -> yellow ellipsis" {
    BATS_PANE_STATES="%0 running"
    run env BATS_PANE_STATES="$BATS_PANE_STATES" bash "$SCRIPT" "work:1"
    [ "$status" -eq 0 ]
    [ "$output" = "$RUNNING_INDICATOR" ]
}

@test "single pane needs-input -> red exclamation" {
    BATS_PANE_STATES="%0 needs-input"
    run env BATS_PANE_STATES="$BATS_PANE_STATES" bash "$SCRIPT" "work:1"
    [ "$status" -eq 0 ]
    [ "$output" = "$NEEDS_INPUT_INDICATOR" ]
}

@test "single pane done -> green checkmark" {
    BATS_PANE_STATES="%0 done"
    run env BATS_PANE_STATES="$BATS_PANE_STATES" bash "$SCRIPT" "work:1"
    [ "$status" -eq 0 ]
    [ "$output" = "$DONE_INDICATOR" ]
}

@test "single pane no state tracked -> empty output" {
    BATS_PANE_STATES="%0"
    run env BATS_PANE_STATES="$BATS_PANE_STATES" bash "$SCRIPT" "work:1"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

# ---------------------------------------------------------------------------
# Multiple panes — priority resolution
# ---------------------------------------------------------------------------

@test "running + needs-input -> needs-input wins" {
    BATS_PANE_STATES="%0 running
%1 needs-input"
    run env BATS_PANE_STATES="$BATS_PANE_STATES" bash "$SCRIPT" "work:1"
    [ "$status" -eq 0 ]
    [ "$output" = "$NEEDS_INPUT_INDICATOR" ]
}

@test "running + done -> running wins" {
    BATS_PANE_STATES="%0 running
%1 done"
    run env BATS_PANE_STATES="$BATS_PANE_STATES" bash "$SCRIPT" "work:1"
    [ "$status" -eq 0 ]
    [ "$output" = "$RUNNING_INDICATOR" ]
}

@test "done + done -> done" {
    BATS_PANE_STATES="%0 done
%1 done"
    run env BATS_PANE_STATES="$BATS_PANE_STATES" bash "$SCRIPT" "work:1"
    [ "$status" -eq 0 ]
    [ "$output" = "$DONE_INDICATOR" ]
}

@test "multiple panes none tracked -> empty output" {
    BATS_PANE_STATES="%0
%1"
    run env BATS_PANE_STATES="$BATS_PANE_STATES" bash "$SCRIPT" "work:1"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "needs-input + done -> needs-input wins" {
    BATS_PANE_STATES="%0 done
%1 needs-input"
    run env BATS_PANE_STATES="$BATS_PANE_STATES" bash "$SCRIPT" "work:1"
    [ "$status" -eq 0 ]
    [ "$output" = "$NEEDS_INPUT_INDICATOR" ]
}

# ---------------------------------------------------------------------------
# Graceful degradation
# ---------------------------------------------------------------------------

@test "no panes at all -> empty output" {
    BATS_PANE_STATES=""
    run env BATS_PANE_STATES="$BATS_PANE_STATES" bash "$SCRIPT" "work:1"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}
