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
	local sessions
	sessions=$(get_sorted_sessions)

	while IFS= read -r session; do
		[[ -z "$session" ]] && continue
		local window_count attached suffix
		window_count=$(tmux list-windows -t "$session" 2>/dev/null | wc -l | tr -d ' ')
		attached=$(tmux display-message -p -t "$session" "#{session_attached}" 2>/dev/null)
		suffix=""
		[[ "$attached" == "1" ]] && suffix=" (attached)"

		printf "%s\t%s: %s windows%s\n" "$session" "$session" "$window_count" "$suffix"

		tmux list-windows -t "$session" -F "#{window_index}|#{window_name}" 2>/dev/null | \
			while IFS='|' read -r idx name; do
				indicator=$("$CURRENT_DIR/window_agent_state.sh" "$session:$idx")
				printf "%s:%s\t  ↳ %s%s\n" "$session" "$idx" "$name" "$indicator"
			done
	done <<< "$sessions"
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
