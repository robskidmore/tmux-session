#!/usr/bin/env bash

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CURRENT="$(tmux display-message -p '#S')"
Z_MODE="off"

source "$CURRENT_DIR/tmuxinator.sh"
source "$CURRENT_DIR/fzf-marks.sh"
source "$CURRENT_DIR/git-branch.sh"

get_sorted_sessions() {
	local sessions
	sessions=$(tmux list-sessions -F "#{session_id} #{session_name}" | sort -n | awk '{print $2}')
	local filtered_sessions
	filtered_sessions=$(tmux show-option -gqv @sessionx-_filtered-sessions)
	if [[ -n "$filtered_sessions" ]]; then
		local filtered_and_piped
		filtered_and_piped=$(echo "$filtered_sessions" | sed -E 's/,/|/g')
		sessions=$(echo "$sessions" | grep -Ev "$filtered_and_piped")
	fi
	echo "$sessions"
}

tmux_option_or_fallback() {
	local option_value
	option_value="$(tmux show-option -gqv "$1")"
	if [ -z "$option_value" ]; then
		option_value="$2"
	fi
	echo "$option_value"
}

input() {
	local filtered_sessions filter_regex=""
	filtered_sessions=$(tmux show-option -gqv @sessionx-_filtered-sessions)
	if [[ -n "$filtered_sessions" ]]; then
		filter_regex="${filtered_sessions//,/|}"
	fi

	local -A pane_state=()
	local env_line env_key env_val pid
	while IFS= read -r env_line; do
		env_key="${env_line%%=*}"
		env_val="${env_line#*=}"
		[[ "$env_key" == TMUX_AGENT_PANE_*_STATE ]] || continue
		pid="${env_key#TMUX_AGENT_PANE_}"
		pid="${pid%_STATE}"
		pane_state[$pid]="$env_val"
	done < <(tmux show-environment -g 2>/dev/null | grep '^TMUX_AGENT_PANE_')

	local -A window_best_prio=() window_best_state=()
	local sname widx pid_var state prio wkey
	while IFS='|' read -r sname widx pid_var; do
		state="${pane_state[$pid_var]:-}"
		[[ -z "$state" ]] && continue
		case "$state" in
			needs-input) prio=2 ;;
			running)     prio=1 ;;
			done)        prio=0 ;;
			*)           prio=-1 ;;
		esac
		wkey="$sname:$widx"
		if [[ -z "${window_best_prio[$wkey]:-}" ]] || (( prio > window_best_prio[$wkey] )); then
			window_best_prio[$wkey]=$prio
			window_best_state[$wkey]=$state
		fi
	done < <(tmux list-panes -a -F '#{session_name}|#{window_index}|#{pane_id}' 2>/dev/null)

	local -A session_windows_buf=()
	local wname indicator
	while IFS='|' read -r sname widx wname; do
		wkey="$sname:$widx"
		state="${window_best_state[$wkey]:-}"
		indicator=""
		case "$state" in
			needs-input) indicator=$' \033[31m!\033[0m' ;;
			running)     indicator=$' \033[33m…\033[0m' ;;
			done)        indicator=$' \033[32m✓\033[0m' ;;
		esac
		session_windows_buf[$sname]+="$sname:$widx"$'\t'"  ↳ $wname$indicator"$'\n'
	done < <(tmux list-windows -a -F '#{session_name}|#{window_index}|#{window_name}' 2>/dev/null)

	local sid swindows sattached suffix
	while IFS='|' read -r sid sname swindows sattached; do
		if [[ -n "$filter_regex" ]] && [[ "$sname" =~ ($filter_regex) ]]; then
			continue
		fi
		suffix=""
		[[ "$sattached" == "1" ]] && suffix=" (attached)"
		printf "%s\t%s: %s windows%s\n" "$sname" "$sname" "$swindows" "$suffix"
		printf "%s" "${session_windows_buf[$sname]:-}"
	done < <(tmux list-sessions -F '#{session_id}|#{session_name}|#{session_windows}|#{session_attached}' 2>/dev/null | sort -n)
}

additional_input() {
	sessions=$(get_sorted_sessions)
	custom_paths=$(tmux show-option -gqv @sessionx-_custom-paths)
	custom_path_subdirectories=$(tmux show-option -gqv @sessionx-_custom-paths-subdirectories)
	if [[ -z "$custom_paths" ]]; then
		echo ""
	else
		clean_paths=$(echo "$custom_paths" | sed -E 's/ *, */,/g' | sed -E 's/^ *//' | sed -E 's/ *$//' | sed -E 's/ /✗/g')
		if [[ "$custom_path_subdirectories" == "true" ]]; then
			paths=$(find ${clean_paths//,/ } -mindepth 1 -maxdepth 1 -type d)
		else
			paths=${clean_paths//,/ }
		fi
		add_path() {
			local path=$1
			if ! grep -q "$(basename "$path")" <<< "$sessions"; then
				printf "%s\t%s\n" "$path" "$path"
			fi
		}
		export -f add_path
		printf "%s\n" "${paths//,/$IFS}" | xargs -n 1 -P 0 bash -c 'add_path "$@"' _
	fi
}

handle_output() {
	# First tab-delimited field is the raw tmux target (session or session:window_index)
	# If no tab present (user typed a new name), the whole string is the target
	local raw
	raw=$(echo "$*" | cut -f1 | tr -d '\n')

	if [ -d "$raw" ]; then
		target="$raw"
	elif is_fzf-marks_mark "$raw"; then
		mark=$(get_fzf-marks_mark "$raw")
		target=$(get_fzf-marks_target "$raw")
	else
		target="$raw"
	fi

	if [[ -z "$target" ]]; then
		exit 0
	fi

	if ! tmux has-session -t="$target" 2>/dev/null; then
		if is_tmuxinator_enabled && is_tmuxinator_template "$target"; then
			tmuxinator start "$target"
		elif test -n "$mark"; then
			tmux new-session -ds "$mark" -c "$target"
			target="$mark"
		elif test -d "$target"; then
			d_target="$(basename "$target" | tr -d '.')"
			tmux new-session -ds $d_target -c "$target"
			target=$d_target
		else
			if [[ "$Z_MODE" == "on" ]]; then
				z_target=$(zoxide query "$target")
				tmux new-session -ds "$target" -c "$z_target" -n "$z_target"
			else
				tmux new-session -ds "$target"
			fi
		fi
	fi
	tmux switch-client -t "$target"

	exit 0
}

handle_input() {
	INPUT=$(input)
	ADDITIONAL_INPUT=$(additional_input)
	if [[ -n $ADDITIONAL_INPUT ]]; then
		INPUT="$(additional_input)\n$INPUT"
	fi
	bind_back=$(tmux show-option -gqv @sessionx-_bind-back)
	git_branch_mode=$(tmux show-option -gqv @sessionx-_git-branch)
	if [[ "$git_branch_mode" == "on" ]]; then
		BACK="$bind_back:reload(${CURRENT_DIR}/sessions_with_branches.sh)+change-preview(${CURRENT_DIR}/preview.sh {1})"
	else
		BACK="$bind_back:reload(echo -e \"${INPUT// /}\")+change-preview(${CURRENT_DIR}/preview.sh {1})"
	fi
}

run_plugin() {
	Z_MODE=$(tmux_option_or_fallback "@sessionx-zoxide-mode" "off")
	eval $(tmux show-option -gqv @sessionx-_built-args)
	eval $(tmux show-option -gqv @sessionx-_built-fzf-opts)
	handle_input
	args+=(--bind "$BACK")

	git_branch_mode=$(tmux show-option -gqv @sessionx-_git-branch)
	if [[ "$git_branch_mode" == "on" ]]; then
		FZF_LISTEN_PORT=$((RANDOM % 10000 + 20000))
		args+=(--listen "localhost:$FZF_LISTEN_PORT")
		args+=(--tiebreak=begin)
		"${CURRENT_DIR}/sessions_with_branches.sh" "$FZF_LISTEN_PORT" &
	fi

	FZF_BUILTIN_TMUX=$(tmux show-option -gqv @sessionx-_fzf-builtin-tmux)
	if [[ "$FZF_BUILTIN_TMUX" == "on" ]]; then
		RESULT=$(echo -e "${INPUT}" | sed -E 's/✗/ /g' | fzf "${fzf_opts[@]}" "${args[@]}" | tail -n1)
	else
		RESULT=$(echo -e "${INPUT}" | sed -E 's/✗/ /g' | fzf-tmux "${fzf_opts[@]}" "${args[@]}" | tail -n1)
	fi
}

run_plugin
handle_output "$RESULT"
