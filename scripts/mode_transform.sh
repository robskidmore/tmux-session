#!/usr/bin/env bash
# Mode-aware key transform for sessionx.
# Called by fzf --bind "KEY:transform:..." bindings.
#
# Args:
#   $1 = key name (enter, esc, j, k, d, r, u, D)
#   $2 = {1} — first tab-delimited field of focused item (tmux target)
#
# Env (set by fzf before running transforms):
#   $FZF_PROMPT — current prompt string
#   $FZF_QUERY  — current query string (used during rename)

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

KEY="$1"
FOCUSED_TARGET="$2"
SESSION="${FOCUSED_TARGET%%:*}"  # strip :window_index if present

NORMAL_PROMPT="$(tmux show-option -gqv '@sessionx-normal-prompt')"
[[ -z "$NORMAL_PROMPT" ]] && NORMAL_PROMPT="N "

INSERT_PROMPT="$(tmux show-option -gqv '@sessionx-prompt')"
[[ -z "$INSERT_PROMPT" ]] && INSERT_PROMPT="❯ "

INSERT_MARKER="❯"
RENAME_MARKER="Rename"

in_insert_mode() { [[ "$FZF_PROMPT" == *"$INSERT_MARKER"* ]]; }
in_rename_mode() { [[ "$FZF_PROMPT" == *"$RENAME_MARKER"* ]]; }

# --- Insert mode ---
if in_insert_mode; then
    case "$KEY" in
        esc)    echo "disable-search+clear-query+change-prompt($NORMAL_PROMPT)" ;;
        enter)  echo "accept" ;;
        change) echo "first" ;;
        *)      echo "put($KEY)" ;;
    esac
    exit 0
fi

# --- Rename mode ---
if in_rename_mode; then
    case "$KEY" in
        esc)
            echo "clear-query+change-prompt($NORMAL_PROMPT)"
            ;;
        change) ;;
        enter)
            QUOTED=$(printf '%q' "$FZF_QUERY")
            if [[ "$FOCUSED_TARGET" == *:* ]]; then
                echo "execute-silent(tmux rename-window -t $FOCUSED_TARGET $QUOTED)+reload($SCRIPTS_DIR/reload_sessions.sh)+clear-query+change-prompt($NORMAL_PROMPT)"
            else
                echo "execute-silent(tmux rename-session -t $SESSION $QUOTED)+reload($SCRIPTS_DIR/reload_sessions.sh)+clear-query+change-prompt($NORMAL_PROMPT)"
            fi
            ;;
        *)
            echo "put($KEY)"
            ;;
    esac
    exit 0
fi

# --- Normal mode ---
case "$KEY" in
    esc)   echo "abort" ;;
    enter) echo "accept" ;;
    i|/)   echo "enable-search+change-prompt($INSERT_PROMPT)" ;;
    j)     echo "down" ;;
    k)     echo "up" ;;
    u)     echo "preview-half-page-up" ;;
    D)     echo "preview-half-page-down" ;;
    d)
        if [[ "$FOCUSED_TARGET" == *:* ]]; then
            echo "execute-silent(tmux kill-window -t $FOCUSED_TARGET)+reload($SCRIPTS_DIR/reload_sessions.sh)"
        else
            echo "execute-silent(tmux kill-session -t $SESSION)+reload($SCRIPTS_DIR/reload_sessions.sh)"
        fi
        ;;
    r)
        if [[ "$FOCUSED_TARGET" == *:* ]]; then
            CURRENT=$(tmux display-message -p -t "$FOCUSED_TARGET" "#{window_name}" 2>/dev/null)
            echo "change-query($CURRENT)+change-prompt(Rename window: )"
        else
            CURRENT=$(tmux display-message -p -t "$SESSION" "#{session_name}" 2>/dev/null)
            echo "change-query($CURRENT)+change-prompt(Rename session: )"
        fi
        ;;
esac
