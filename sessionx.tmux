#!/usr/bin/env bash

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$CURRENT_DIR/scripts"
CURRENT="$(tmux display-message -p '#S')"

source "$SCRIPTS_DIR/tmuxinator.sh"
source "$SCRIPTS_DIR/fzf-marks.sh"

tmux_option_or_fallback() {
	local option_value
	option_value="$(tmux show-option -gqv "$1")"
	if [ -z "$option_value" ]; then
		option_value="$2"
	fi
	echo "$option_value"
}

preview_settings() {
	default_window_mode=$(tmux_option_or_fallback "@sessionx-window-mode" "off")
	if [[ "$default_window_mode" == "on" ]]; then
		PREVIEW_OPTIONS="-w"
	fi
	default_window_mode=$(tmux_option_or_fallback "@sessionx-tree-mode" "off")
	if [[ "$default_window_mode" == "on" ]]; then
		PREVIEW_OPTIONS="-t"
	fi
	preview_location=$(tmux_option_or_fallback "@sessionx-preview-location" "right")
	preview_ratio=$(tmux_option_or_fallback "@sessionx-preview-ratio" "55%")
	preview_enabled=$(tmux_option_or_fallback "@sessionx-preview-enabled" "true")
}

window_settings() {
	window_height=$(tmux_option_or_fallback "@sessionx-window-height" "75%")
	window_width=$(tmux_option_or_fallback "@sessionx-window-width" "75%")
	layout_mode=$(tmux_option_or_fallback "@sessionx-layout" "reverse")
	prompt_icon=$(tmux_option_or_fallback "@sessionx-prompt" "❯ ")
	normal_prompt_icon=$(tmux_option_or_fallback "@sessionx-normal-prompt" "N ")
	pointer_icon=$(tmux_option_or_fallback "@sessionx-pointer" "▶")
}

handle_binds() {
	bind_configuration_mode=$(tmux_option_or_fallback "@sessionx-bind-configuration-path" "ctrl-x")
	bind_rename_session=$(tmux_option_or_fallback "@sessionx-bind-rename-session" "ctrl-r")
	additional_fzf_options=$(tmux_option_or_fallback "@sessionx-additional-options" "--color pointer:9,spinner:92,marker:46")

	bind_back=$(tmux_option_or_fallback "@sessionx-bind-back" "ctrl-b")
	bind_new_window=$(tmux_option_or_fallback "@sessionx-bind-new-window" "ctrl-e")
	bind_zo=$(tmux_option_or_fallback "@sessionx-bind-zo-new-window" "ctrl-f")
	bind_kill_session=$(tmux_option_or_fallback "@sessionx-bind-kill-session" "alt-bspace")

	bind_exit=$(tmux_option_or_fallback "@sessionx-bind-abort" "esc")
	bind_accept=$(tmux_option_or_fallback "@sessionx-bind-accept" "enter")
	bind_delete_char=$(tmux_option_or_fallback "@sessionx-bind-delete-char" "bspace")

	bind_scroll_up=$(tmux_option_or_fallback "@sessionx-bind-scroll-up" "ctrl-u")
	bind_scroll_down=$(tmux_option_or_fallback "@sessionx-bind-scroll-down" "ctrl-d")

	bind_select_up=$(tmux_option_or_fallback "@sessionx-bind-select-up" "ctrl-p")
	bind_select_down=$(tmux_option_or_fallback "@sessionx-bind-select-down" "ctrl-n")

}

handle_args() {
	LS_COMMAND=$(tmux_option_or_fallback "@sessionx-ls-command" "ls")
	if [[ "$preview_enabled" == "true" ]]; then
		PREVIEW_LINE="${SCRIPTS_DIR%/}/preview.sh {1}"
	fi
	CONFIGURATION_PATH=$(tmux_option_or_fallback "@sessionx-x-path" "$HOME/.config")
	FZF_BUILTIN_TMUX=$(tmux_option_or_fallback "@sessionx-fzf-builtin-tmux" "off")

	CONFIGURATION_MODE="$bind_configuration_mode:reload(find -L $CONFIGURATION_PATH -mindepth 1 -maxdepth 1 -type d -o -type l)+change-preview($LS_COMMAND {1})"

	NEW_WINDOW="$bind_new_window:reload(find -L $PWD -mindepth 1 -maxdepth 1 -type d -o -type l)+change-preview($LS_COMMAND {1})"
	ZO_WINDOW="$bind_zo:reload(zoxide query -l)+change-preview($LS_COMMAND {1})"
	KILL_SESSION="$bind_kill_session:execute-silent(tmux kill-session -t \$(echo {1} | cut -d: -f1))+reload(${SCRIPTS_DIR%/}/reload_sessions.sh)"

	ACCEPT="$bind_accept:transform:${SCRIPTS_DIR%/}/mode_transform.sh enter {1}"
	DELETE="$bind_delete_char:backward-delete-char"
	ENTER_INSERT="i:transform:${SCRIPTS_DIR%/}/mode_transform.sh i {1}"
	ENTER_INSERT_SLASH="/:transform:${SCRIPTS_DIR%/}/mode_transform.sh / {1}"
	ESC_TRANSFORM="esc:transform:${SCRIPTS_DIR%/}/mode_transform.sh esc {1}"
	J_TRANSFORM="j:transform:${SCRIPTS_DIR%/}/mode_transform.sh j {1}"
	K_TRANSFORM="k:transform:${SCRIPTS_DIR%/}/mode_transform.sh k {1}"
	D_TRANSFORM="d:transform:${SCRIPTS_DIR%/}/mode_transform.sh d {1}"
	R_TRANSFORM="r:transform:${SCRIPTS_DIR%/}/mode_transform.sh r {1}"
	U_TRANSFORM="u:transform:${SCRIPTS_DIR%/}/mode_transform.sh u {1}"
	SHIFT_D_TRANSFORM="D:transform:${SCRIPTS_DIR%/}/mode_transform.sh D {1}"

	SELECT_UP="$bind_select_up:up"
	SELECT_DOWN="$bind_select_down:down"
	SCROLL_UP="$bind_scroll_up:preview-half-page-up"
	SCROLL_DOWN="$bind_scroll_down:preview-half-page-down"

	RENAME_SESSION_EXEC='bash -c '\'' printf >&2 "New name: ";read name; tmux rename-session -t $(echo {1} | cut -d: -f1) "${name}"; '\'''
	RENAME_SESSION_RELOAD='bash -c '\'' ${SCRIPTS_DIR%/}/reload_sessions.sh; '\'''
	RENAME_SESSION="$bind_rename_session:execute($RENAME_SESSION_EXEC)+reload($RENAME_SESSION_RELOAD)"

	HEADER="$bind_accept=󰿄  $bind_kill_session=󱂧  $bind_rename_session=󰑕  $bind_configuration_mode=󱃖  $bind_new_window=󰇘  $bind_back=󰌍  $bind_scroll_up=  $bind_scroll_down= / $bind_zo="
	if is_fzf-marks_enabled; then
		HEADER="$HEADER  $(get_fzf-marks_keybind)=󰣉"
	fi

	if [[ "$FZF_BUILTIN_TMUX" == "on" ]]; then
		fzf_size_arg="--tmux"
	else
		fzf_size_arg="-p"
	fi

	args=(
		--ansi
		--border=rounded
		--disabled
		--delimiter=$'\t'
		--with-nth=2..
		--info=inline-right
		--no-separator
		--bind "$CONFIGURATION_MODE"
		--bind "$NEW_WINDOW"
		--bind "$ZO_WINDOW"
		--bind "$KILL_SESSION"
		--bind "$DELETE"
		--bind "$ESC_TRANSFORM"
		--bind "$J_TRANSFORM"
		--bind "$K_TRANSFORM"
		--bind "$D_TRANSFORM"
		--bind "$R_TRANSFORM"
		--bind "$U_TRANSFORM"
		--bind "$SHIFT_D_TRANSFORM"
		--bind "$ENTER_INSERT"
		--bind "$ENTER_INSERT_SLASH"
		--bind "$SELECT_UP"
		--bind "$SELECT_DOWN"
		--bind "$ACCEPT"
		--bind "$SCROLL_UP"
		--bind "$SCROLL_DOWN"
		--bind "$RENAME_SESSION"
		--bind '?:toggle-preview'
		--bind "change:transform:${SCRIPTS_DIR%/}/mode_transform.sh change {1}"
		--exit-0
		--preview="${PREVIEW_LINE}"
		--preview-window="${preview_location},${preview_ratio},border-left"
		--layout="$layout_mode"
		--pointer="$pointer_icon"
		"${fzf_size_arg}" "$window_width,$window_height"
		--prompt "$normal_prompt_icon"
		--print-query
		--scrollbar '▌▐'
	)

	legacy=$(tmux_option_or_fallback "@sessionx-legacy-fzf-support" "off")
	if [[ "${legacy}" == "off" ]]; then
		args+=(--border-label "  $CURRENT  ")
		args+=(--preview-label-pos=0)
		args+=(--bind 'focus:transform-preview-label:echo [ {2..} ] | sed "s/\x1b\[[0-9;]*m//g"')
	fi
	auto_accept=$(tmux_option_or_fallback "@sessionx-auto-accept" "off")
	if [[ "${auto_accept}" == "on" ]]; then
		args+=(--bind one:accept)
	fi

	if $(is_tmuxinator_enabled); then
		args+=(--bind "$(load_tmuxinator_binding)")
	fi
	if $(is_fzf-marks_enabled); then
		args+=(--bind "$(load_fzf-marks_binding)")
	fi

	eval "fzf_opts=($additional_fzf_options)"
}

handle_extra_options() {
	# Store each option individually to avoid bash 3.2 associative array issues on macOS
	tmux set-option -g @sessionx-_bind-back "$bind_back"
	tmux set-option -g @sessionx-_filtered-sessions "$(tmux_option_or_fallback "@sessionx-filtered-sessions" "")"
	tmux set-option -g @sessionx-_window-mode "$(tmux_option_or_fallback "@sessionx-window-mode" "off")"
	tmux set-option -g @sessionx-_filter-current "$(tmux_option_or_fallback "@sessionx-filter-current" "true")"
	tmux set-option -g @sessionx-_custom-paths "$(tmux_option_or_fallback "@sessionx-custom-paths" "")"
	tmux set-option -g @sessionx-_custom-paths-subdirectories "$(tmux_option_or_fallback "@sessionx-custom-paths-subdirectories" "false")"
	tmux set-option -g @sessionx-_git-branch "$(tmux_option_or_fallback "@sessionx-git-branch" "off")"
	tmux set-option -g @sessionx-_fzf-builtin-tmux "$FZF_BUILTIN_TMUX"
}

preview_settings
window_settings
handle_binds
handle_args
handle_extra_options

tmux set-option -g @sessionx-_built-args "$(declare -p args)"
tmux set-option -g @sessionx-_built-fzf-opts "$(declare -p fzf_opts)"

if [ `tmux_option_or_fallback "@sessionx-prefix" "on"` = "on"  ]; then
	tmux bind-key "$(tmux_option_or_fallback "@sessionx-bind" "O")" run-shell "$CURRENT_DIR/scripts/sessionx.sh"
else
	tmux bind-key -n "$(tmux_option_or_fallback "@sessionx-bind" "O")" run-shell "$CURRENT_DIR/scripts/sessionx.sh"
fi
