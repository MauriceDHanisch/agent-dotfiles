#!/bin/bash

data=$(cat)

# Parse JSON with jq
eval "$(echo "$data" | jq -r '
  @sh "model=\(.model.display_name // "Claude" | sub(" \\(.*"; ""))",
  @sh "directory=\(.workspace.current_dir // "." | split("/") | last)",
  @sh "pct=\(.context_window.used_percentage // 0 | floor)",
  @sh "window_size=\(.context_window.context_window_size // 0)",
  @sh "used_tokens=\((.context_window.total_input_tokens // 0) + (.context_window.total_output_tokens // 0))",
  @sh "thinking=\(.thinking.enabled // false)",
  @sh "effort=\(.effort.level // "")",
  @sh "five_h=\(.rate_limits.five_hour.used_percentage // "" | if . == "" then . else floor end)",
  @sh "five_h_secs=\(.rate_limits.five_hour.resets_at // "" | if . == "" then . else . - now | floor end)",
  @sh "seven_d=\(.rate_limits.seven_day.used_percentage // "" | if . == "" then . else floor end)",
  @sh "reset_date=\(.rate_limits.seven_day.resets_at // "" | if . == "" then . else strflocaltime("%a %H:%M") end)",
  @sh "transcript=\(.transcript_path // "")",
  @sh "session_id=\(.session_id // "")",
  @sh "in_raw=\(.context_window.current_usage.input_tokens // 0)",
  @sh "cache_w=\(.context_window.current_usage.cache_creation_input_tokens // 0)",
  @sh "cache_r=\(.context_window.current_usage.cache_read_input_tokens // 0)",
  @sh "last_out=\(.context_window.current_usage.output_tokens // 0)"
')"

# Models of running subagents: not interrupted, last assistant turn not end_turn, written in the last 5 min
agents_file="/tmp/claude-agents-${session_id}"
IFS=$'\t' read -r viewed_model viewed_effort 2>/dev/null < "/tmp/claude-view-${session_id}"
if [ -n "$viewed_model" ]; then
    model="⤷ ${viewed_model}"
    effort="$viewed_effort"
    [ -n "$effort" ] || thinking=""
fi
if [ -f "$agents_file" ]; then
    sub_models=$(<"$agents_file")
else
    sub_models=$(for f in $(find "${transcript%.jsonl}/subagents" -name 'agent-*.jsonl' -newermt '-5 minutes' 2>/dev/null); do
        tail -1 "$f" | grep -q 'Request interrupted by user' && continue
        grep -h '"model"' "$f" | tail -1 | jq -r 'select(.message.stop_reason != "end_turn") | .message.model // empty'
    done | sed 's/^claude-//; s/-[0-9].*//' | sort | uniq -c | awk '{printf " %s x%s", $2, $1}' | sed 's/^ //')
fi

# Colors
BLUE=$'\e[38;2;140;200;240m'
BBLUE=$'\e[1;38;2;140;200;240m'
DGREY=$'\e[38;2;120;120;120m'
LGREY=$'\e[38;2;210;210;210m'
WHITE=$'\e[38;2;240;240;240m'
GREY=$'\e[38;2;175;175;175m'
RESET=$'\e[0m'

# Git branch
branch=$(git branch --show-current 2>/dev/null || echo "")
branch_str=""
[ -n "$branch" ] && branch_str=" ${DGREY}🌿${RESET} ${LGREY}${branch}${RESET}"

# Token window: used / total
format_tokens() {
    local n=$1
    if [ "$n" -ge 1000000 ]; then
        printf "%d.%dM" $(((n + 50000) / 1000000)) $((((n + 50000) % 1000000) / 100000))
    elif [ "$n" -ge 1000 ]; then
        printf "%dk" $(((n + 500) / 1000))
    else
        echo "$n"
    fi
}

used_fmt=$(format_tokens "$used_tokens")
window_fmt=$(format_tokens "$window_size")

# Bar color
if [ "$pct" -lt 50 ]; then
    bar_color=$'\e[38;2;100;210;100m'
elif [ "$pct" -lt 75 ]; then
    bar_color=$'\e[38;2;210;180;50m'
elif [ "$pct" -lt 90 ]; then
    bar_color=$'\e[38;2;220;120;40m'
else
    bar_color=$'\e[38;2;200;60;60m'
fi

# Build bar
filled=$((pct * 12 / 100))
empty=$((12 - filled))
printf -v bar_fill '%*s' "$filled" ''
bar_fill=${bar_fill// /━}
printf -v bar_empty '%*s' "$empty" ''

last_in=$((in_raw + cache_w + cache_r))
last_str=""
if [ "$last_in" -gt 0 ]; then
    last_str=" ${DGREY}│${RESET} ${WHITE}last:${RESET} ${GREY}↑$(format_tokens "$last_in") ↓$(format_tokens "$last_out")${RESET} ${BLUE}$((cache_r * 100 / last_in))% cached${RESET}"
fi

# Build rate limit string with reset times
rate_str=""
if [ -n "$five_h" ] && [ "$five_h" != "empty" ]; then
    rate_str="${rate_str}${WHITE}5h:${RESET} ${BLUE}${five_h}%${RESET}"
    if [ -n "$five_h_secs" ]; then
        secs=$five_h_secs
        if [ $secs -gt 0 ]; then
            mins=$((secs / 60))
            hours=$((mins / 60))
            mins=$((mins % 60))
            if [ $hours -gt 0 ]; then
                rate_str="${rate_str} ${LGREY}(${hours}h ${mins}m)${RESET}"
            else
                rate_str="${rate_str} ${LGREY}(${mins}m)${RESET}"
            fi
        fi
    fi
fi

if [ -n "$seven_d" ] && [ "$seven_d" != "empty" ]; then
    rate_str="${rate_str} ${DGREY}│${RESET} ${WHITE}7d:${RESET} ${BLUE}${seven_d}%${RESET}"
    [ -n "$reset_date" ] && rate_str="${rate_str} ${LGREY}(${reset_date})${RESET}"
fi

# Thinking & effort — appended inside model brackets, non-bold blue
after_model=""
[ "$thinking" = "true" ] && after_model="${after_model} 🧠"
[ -n "$effort" ] && [ "$effort" != "null" ] && after_model="${after_model} ${WHITE}${effort}${RESET}"

# Output - clean two lines
echo "${BBLUE}[${model}]${RESET} ${DGREY}│${RESET}${after_model:+${after_model} ${DGREY}│${RESET}} ${DGREY}📁${RESET} ${WHITE}${directory}${RESET}${branch_str}"
echo "${LGREY}[${RESET}${bar_color}${bar_fill}${RESET}${bar_empty}${LGREY}]${RESET} ${bar_color}${pct}%${RESET} ${GREY}${used_fmt}/${window_fmt}${RESET}${last_str}"
echo "${rate_str}${rate_str:+ ${DGREY}│${RESET} }${WHITE}agents:${RESET}${BLUE} ${sub_models:-none}${RESET}"
