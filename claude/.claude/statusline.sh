#!/bin/bash

data=$(cat)

# Parse JSON with jq
model=$(echo "$data" | jq -r '.model.display_name // "Claude"' | sed 's/ (.*)//')
directory=$(echo "$data" | jq -r '.workspace.current_dir // "."' | xargs basename)
pct=$(echo "$data" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
window_size=$(echo "$data" | jq -r '.context_window.context_window_size // 0')
used_tokens=$(echo "$data" | jq -r '(.context_window.total_input_tokens // 0) + (.context_window.total_output_tokens // 0)')
thinking=$(echo "$data" | jq -r '.thinking.enabled // false')
effort=$(echo "$data" | jq -r '.effort.level // ""')
five_h=$(echo "$data" | jq -r '.rate_limits.five_hour.used_percentage // empty' | cut -d. -f1)
five_h_reset=$(echo "$data" | jq -r '.rate_limits.five_hour.resets_at // empty')
seven_d=$(echo "$data" | jq -r '.rate_limits.seven_day.used_percentage // empty' | cut -d. -f1)
seven_d_reset=$(echo "$data" | jq -r '.rate_limits.seven_day.resets_at // empty')
transcript=$(echo "$data" | jq -r '.transcript_path // empty')
in_raw=$(echo "$data" | jq -r '.context_window.current_usage.input_tokens // 0')
cache_w=$(echo "$data" | jq -r '.context_window.current_usage.cache_creation_input_tokens // 0')
cache_r=$(echo "$data" | jq -r '.context_window.current_usage.cache_read_input_tokens // 0')
last_out=$(echo "$data" | jq -r '.context_window.current_usage.output_tokens // 0')

# Models of running subagents: not interrupted, last assistant turn not end_turn, written in the last 5 min
sub_models=$(for f in $(find "${transcript%.jsonl}/subagents" -name 'agent-*.jsonl' -newermt '-5 minutes' 2>/dev/null); do
    tail -1 "$f" | grep -q 'Request interrupted by user' && continue
    grep -h '"model"' "$f" | tail -1 | jq -r 'select(.message.stop_reason != "end_turn") | .message.model // empty'
done | sed 's/^claude-//; s/-[0-9].*//' | sort | uniq -c | awk '{printf " %s x%s", $2, $1}')

# Cross-platform epoch-to-date helper: epoch_to_date <epoch> <format>
epoch_to_date() {
    if [[ "$(uname)" == "Darwin" ]]; then
        date -r "$1" +"$2" 2>/dev/null
    else
        date -d "@$1" +"$2" 2>/dev/null
    fi
}

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
        printf "%.1fM" "$(echo "$n / 1000000" | bc -l)"
    elif [ "$n" -ge 1000 ]; then
        printf "%.0fk" "$(echo "$n / 1000" | bc -l)"
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
bar_fill=$(printf '━%.0s' $(seq 1 "$filled"))
bar_empty=$(printf ' %.0s' $(seq 1 "$empty"))

last_in=$((in_raw + cache_w + cache_r))
last_str=""
if [ "$last_in" -gt 0 ]; then
    last_str=" ${DGREY}│${RESET} ${WHITE}last:${RESET} ${GREY}↑$(format_tokens "$last_in") ↓$(format_tokens "$last_out")${RESET} ${BLUE}$((cache_r * 100 / last_in))% cached${RESET}"
fi

# Build rate limit string with reset times
rate_str=""
if [ -n "$five_h" ] && [ "$five_h" != "empty" ]; then
    rate_str="${rate_str}${WHITE}5h:${RESET} ${BLUE}${five_h}%${RESET}"
    if [ -n "$five_h_reset" ] && [ "$five_h_reset" != "empty" ]; then
        now=$(date +%s)
        secs=$((five_h_reset - now))
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
    if [ -n "$seven_d_reset" ] && [ "$seven_d_reset" != "empty" ]; then
        now=$(date +%s)
        reset_date=$(epoch_to_date "$seven_d_reset" "%a %H:%M")
        [ -n "$reset_date" ] && rate_str="${rate_str} ${LGREY}(${reset_date})${RESET}"
    fi
fi

# Thinking & effort — appended inside model brackets, non-bold blue
BLUE_NB=$'\e[38;2;140;200;240m'
model_suffix=""

after_model=""
[ "$thinking" = "true" ] && after_model="${after_model} 🧠"
[ -n "$effort" ] && [ "$effort" != "null" ] && after_model="${after_model} ${WHITE}${effort}${RESET}"

# Output - clean two lines
echo "${BBLUE}[${model}]${RESET} ${DGREY}│${RESET}${after_model} ${DGREY}│${RESET} ${DGREY}📁${RESET} ${WHITE}${directory}${RESET}${branch_str}"
echo "${LGREY}[${RESET}${bar_color}${bar_fill}${RESET}${bar_empty}${LGREY}]${RESET} ${bar_color}${pct}%${RESET} ${GREY}${used_fmt}/${window_fmt}${RESET}${last_str}"
echo "${rate_str}${rate_str:+ ${DGREY}│${RESET} }${WHITE}agents:${RESET}${BLUE}${sub_models:- none}${RESET}"
