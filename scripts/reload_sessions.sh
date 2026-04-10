#!/usr/bin/env bash
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ordered=$(tmux list-sessions -F "#{session_id} #{session_name}" | sort -n | awk '{print $2}')

while IFS= read -r session; do
	[[ -z "$session" ]] && continue
	window_count=$(tmux list-windows -t "$session" 2>/dev/null | wc -l | tr -d ' ')
	attached=$(tmux display-message -p -t "$session" "#{session_attached}" 2>/dev/null)
	suffix=""
	[[ "$attached" == "1" ]] && suffix=" (attached)"

	printf "%s\t%s: %s windows%s\n" "$session" "$session" "$window_count" "$suffix"

	tmux list-windows -t "$session" -F "#{window_index}|#{window_name}" 2>/dev/null | \
		while IFS='|' read -r idx name; do
			printf "%s:%s\t  ↳ %s\n" "$session" "$idx" "$name"
		done
done <<< "$ordered"
