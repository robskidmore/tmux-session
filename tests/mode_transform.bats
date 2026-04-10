#!/usr/bin/env bats
# Tests for scripts/mode_transform.sh
# Run with: bats tests/mode_transform.bats
#
# mode_transform.sh is tested as a pure function:
#   - set FZF_PROMPT / FZF_QUERY to control mode and query state
#   - pass key + focused_target as arguments
#   - assert the fzf action string written to stdout

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/mode_transform.sh"

# Override tmux to return a predictable name without a real tmux session
tmux() {
    case "$*" in
        *window_name*) echo "svc-auth" ;;
        *session_name*) echo "Nostra" ;;
        *) echo "" ;;
    esac
}
export -f tmux

NORMAL_PROMPT="N "
INSERT_PROMPT="❯ "
RENAME_SESSION_PROMPT="Rename session: "
RENAME_WINDOW_PROMPT="Rename window: "

# ---------------------------------------------------------------------------
# Normal mode (FZF_PROMPT does not contain ❯ or Rename)
# ---------------------------------------------------------------------------

@test "normal mode: j -> down" {
    run env FZF_PROMPT="$NORMAL_PROMPT" bash "$SCRIPT" j ""
    [ "$status" -eq 0 ]
    [ "$output" = "down" ]
}

@test "normal mode: k -> up" {
    run env FZF_PROMPT="$NORMAL_PROMPT" bash "$SCRIPT" k ""
    [ "$status" -eq 0 ]
    [ "$output" = "up" ]
}

@test "normal mode: u -> preview-half-page-up" {
    run env FZF_PROMPT="$NORMAL_PROMPT" bash "$SCRIPT" u ""
    [ "$status" -eq 0 ]
    [ "$output" = "preview-half-page-up" ]
}

@test "normal mode: D -> preview-half-page-down" {
    run env FZF_PROMPT="$NORMAL_PROMPT" bash "$SCRIPT" D ""
    [ "$status" -eq 0 ]
    [ "$output" = "preview-half-page-down" ]
}

@test "normal mode: esc -> abort" {
    run env FZF_PROMPT="$NORMAL_PROMPT" bash "$SCRIPT" esc ""
    [ "$status" -eq 0 ]
    [ "$output" = "abort" ]
}

@test "normal mode: i -> enable-search+change-prompt(insert)" {
    run env FZF_PROMPT="$NORMAL_PROMPT" bash "$SCRIPT" i ""
    [ "$status" -eq 0 ]
    [[ "$output" == "enable-search+change-prompt("* ]]
}

@test "normal mode: / -> enable-search+change-prompt(insert)" {
    run env FZF_PROMPT="$NORMAL_PROMPT" bash "$SCRIPT" / ""
    [ "$status" -eq 0 ]
    [[ "$output" == "enable-search+change-prompt("* ]]
}

@test "normal mode: enter -> accept" {
    run env FZF_PROMPT="$NORMAL_PROMPT" bash "$SCRIPT" enter "Nostra"
    [ "$status" -eq 0 ]
    [ "$output" = "accept" ]
}

@test "normal mode: d with session target kills session" {
    run env FZF_PROMPT="$NORMAL_PROMPT" bash "$SCRIPT" d "Nostra"
    [ "$status" -eq 0 ]
    [[ "$output" == *"kill-session -t Nostra"* ]]
}

@test "normal mode: d with window target kills window" {
    run env FZF_PROMPT="$NORMAL_PROMPT" bash "$SCRIPT" d "Nostra:2"
    [ "$status" -eq 0 ]
    [[ "$output" == *"kill-window -t Nostra:2"* ]]
    [[ "$output" != *"kill-session"* ]]
}

@test "normal mode: r on session target enters rename-session mode" {
    run env FZF_PROMPT="$NORMAL_PROMPT" bash "$SCRIPT" r "Nostra"
    [ "$status" -eq 0 ]
    [[ "$output" == *"change-prompt(Rename session: )"* ]]
    [[ "$output" == *"change-query("* ]]
    [[ "$output" != *"rename-session"* ]]
}

@test "normal mode: r on window target enters rename-window mode" {
    run env FZF_PROMPT="$NORMAL_PROMPT" bash "$SCRIPT" r "Nostra:2"
    [ "$status" -eq 0 ]
    [[ "$output" == *"change-prompt(Rename window: )"* ]]
    [[ "$output" == *"change-query("* ]]
    [[ "$output" != *"rename-window"* ]]
}

# ---------------------------------------------------------------------------
# Rename mode (FZF_PROMPT contains "Rename")
# ---------------------------------------------------------------------------

@test "rename mode: esc cancels and restores normal prompt" {
    run env FZF_PROMPT="$RENAME_SESSION_PROMPT" bash "$SCRIPT" esc "Nostra"
    [ "$status" -eq 0 ]
    [[ "$output" == *"clear-query"* ]]
    [[ "$output" == *"change-prompt(N )"* ]]
    [[ "$output" != *"abort"* ]]
}

@test "rename mode: enter on session applies rename-session" {
    run env FZF_PROMPT="$RENAME_SESSION_PROMPT" FZF_QUERY="new-name" bash "$SCRIPT" enter "Nostra"
    [ "$status" -eq 0 ]
    [[ "$output" == *"rename-session -t Nostra"* ]]
    [[ "$output" == *"new-name"* ]]
    [[ "$output" == *"change-prompt(N )"* ]]
}

@test "rename mode: enter on window applies rename-window" {
    run env FZF_PROMPT="$RENAME_WINDOW_PROMPT" FZF_QUERY="new-win" bash "$SCRIPT" enter "Nostra:2"
    [ "$status" -eq 0 ]
    [[ "$output" == *"rename-window -t Nostra:2"* ]]
    [[ "$output" == *"new-win"* ]]
    [[ "$output" == *"change-prompt(N )"* ]]
}

@test "rename mode: enter reloads list after rename" {
    run env FZF_PROMPT="$RENAME_SESSION_PROMPT" FZF_QUERY="new-name" bash "$SCRIPT" enter "Nostra"
    [ "$status" -eq 0 ]
    [[ "$output" == *"reload("* ]]
}

@test "rename mode: other keys insert character into query" {
    run env FZF_PROMPT="$RENAME_SESSION_PROMPT" bash "$SCRIPT" D "Nostra"
    [ "$status" -eq 0 ]
    [ "$output" = "put(D)" ]
}

@test "rename mode: i -> put(i)" {
    run env FZF_PROMPT="$RENAME_SESSION_PROMPT" bash "$SCRIPT" i "Nostra"
    [ "$status" -eq 0 ]
    [ "$output" = "put(i)" ]
}

# ---------------------------------------------------------------------------
# Insert mode (FZF_PROMPT contains ❯)
# ---------------------------------------------------------------------------

@test "insert mode: j -> put(j)" {
    run env FZF_PROMPT="$INSERT_PROMPT" bash "$SCRIPT" j ""
    [ "$status" -eq 0 ]
    [ "$output" = "put(j)" ]
}

@test "insert mode: k -> put(k)" {
    run env FZF_PROMPT="$INSERT_PROMPT" bash "$SCRIPT" k ""
    [ "$status" -eq 0 ]
    [ "$output" = "put(k)" ]
}

@test "insert mode: d -> put(d)" {
    run env FZF_PROMPT="$INSERT_PROMPT" bash "$SCRIPT" d ""
    [ "$status" -eq 0 ]
    [ "$output" = "put(d)" ]
}

@test "insert mode: r -> put(r)" {
    run env FZF_PROMPT="$INSERT_PROMPT" bash "$SCRIPT" r ""
    [ "$status" -eq 0 ]
    [ "$output" = "put(r)" ]
}

@test "insert mode: u -> put(u)" {
    run env FZF_PROMPT="$INSERT_PROMPT" bash "$SCRIPT" u ""
    [ "$status" -eq 0 ]
    [ "$output" = "put(u)" ]
}

@test "insert mode: D -> put(D)" {
    run env FZF_PROMPT="$INSERT_PROMPT" bash "$SCRIPT" D ""
    [ "$status" -eq 0 ]
    [ "$output" = "put(D)" ]
}

@test "insert mode: enter -> accept" {
    run env FZF_PROMPT="$INSERT_PROMPT" bash "$SCRIPT" enter ""
    [ "$status" -eq 0 ]
    [ "$output" = "accept" ]
}

@test "insert mode: esc -> disable-search+clear-query+change-prompt" {
    run env FZF_PROMPT="$INSERT_PROMPT" bash "$SCRIPT" esc ""
    [ "$status" -eq 0 ]
    [[ "$output" == "disable-search+clear-query+change-prompt("* ]]
}

@test "insert mode: change -> first" {
    run env FZF_PROMPT="$INSERT_PROMPT" bash "$SCRIPT" change ""
    [ "$status" -eq 0 ]
    [ "$output" = "first" ]
}

@test "normal mode: change -> no-op" {
    run env FZF_PROMPT="$NORMAL_PROMPT" bash "$SCRIPT" change ""
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "rename mode: change -> no-op" {
    run env FZF_PROMPT="$RENAME_SESSION_PROMPT" bash "$SCRIPT" change "Nostra"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "insert mode: esc restores normal prompt" {
    run env FZF_PROMPT="$INSERT_PROMPT" bash "$SCRIPT" esc ""
    [ "$status" -eq 0 ]
    [[ "$output" == *"change-prompt(N )"* ]]
}
