#!/bin/bash

data=$(cat)
# Log input for further debugging if needed
# echo "$data" > /home/maurice/statusline_debug.json

# Parse JSON with jq
model_name=$(echo "$data" | jq -r '.model.display_name // .active_model // "Antigravity"')
model=$(echo "$model_name" | sed 's/ (.*)//')
cwd=$(echo "$data" | jq -r '.workspace.current_dir // .cwd // "."')
directory=$(basename "$cwd")
pct=$(echo "$data" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
window_size=$(echo "$data" | jq -r '.context_window.context_window_size // 0')
used_tokens=$(echo "$data" | jq -r '(.context_window.total_input_tokens // 0) + (.context_window.total_output_tokens // 0)')
state=$(echo "$data" | jq -r '.agent_state // ""')
tier=$(echo "$data" | jq -r '.plan_tier // ""' | sed 's/Google AI //')

# Rate limits / Fuel tank
five_h=$(echo "$data" | jq -r '.rate_limits.five_hour.used_percentage // .fuel_tank.five_hour.used_percentage // empty' | cut -d. -f1)
five_h_reset=$(echo "$data" | jq -r '.rate_limits.five_hour.resets_at // .fuel_tank.five_hour.resets_at // empty')
seven_d=$(echo "$data" | jq -r '.rate_limits.seven_day.used_percentage // .fuel_tank.seven_day.used_percentage // empty' | cut -d. -f1)
seven_d_reset=$(echo "$data" | jq -r '.rate_limits.seven_day.resets_at // .fuel_tank.seven_day.resets_at // empty')

# Cross-platform epoch-to-date helper
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
branch=$(git -C "$cwd" branch --show-current 2>/dev/null || echo "")
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
[ "$filled" -lt 0 ] && filled=0
[ "$empty" -lt 0 ] && empty=0
bar_fill=$(printf '━%.0s' $(seq 1 "$filled" 2>/dev/null))
bar_empty=$(printf ' %.0s' $(seq 1 "$empty" 2>/dev/null))

# Build rate limit string
rate_str=""
if [ -n "$five_h" ] && [ "$five_h" != "empty" ]; then
    rate_str="${rate_str} ${DGREY}│${RESET} ${WHITE}5h:${RESET} ${BLUE}${five_h}%${RESET}"
    if [ -n "$five_h_reset" ] && [ "$five_h_reset" != "empty" ]; then
        now=$(date +%s)
        secs=$((five_h_reset - now))
        if [ $secs -gt 0 ]; then
            mins=$((secs / 60))
            hours=$((mins / 60))
            mins=$((mins % 60))
            [ $hours -gt 0 ] && rate_str="${rate_str} ${LGREY}(${hours}h ${mins}m)${RESET}" || rate_str="${rate_str} ${LGREY}(${mins}m)${RESET}"
        fi
    fi
fi

if [ -n "$seven_d" ] && [ "$seven_d" != "empty" ]; then
    rate_str="${rate_str} ${DGREY}│${RESET} ${WHITE}7d:${RESET} ${BLUE}${seven_d}%${RESET}"
    if [ -n "$seven_d_reset" ] && [ "$seven_d_reset" != "empty" ]; then
        reset_date=$(epoch_to_date "$seven_d_reset" "%a %H:%M")
        [ -n "$reset_date" ] && rate_str="${rate_str} ${LGREY}(${reset_date})${RESET}"
    fi
fi

# Fallback for limits if missing: show Tier
if [ -z "$rate_str" ] && [ -n "$tier" ]; then
    rate_str=" ${DGREY}│${RESET} ${BLUE}${tier}${RESET}"
fi

after_model=""
# Check thinking state
if [ "$state" = "thinking" ] || [ "$state" = "reasoning" ] || [ "$(echo "$data" | jq -r '.thinking.enabled // false')" = "true" ]; then
    after_model="${after_model} 🧠"
fi

# Output - clean two lines
echo "${BBLUE}[${model}]${RESET} ${DGREY}│${RESET}${after_model} ${DGREY}│${RESET} ${DGREY}📁${RESET} ${WHITE}${directory}${RESET}${branch_str} ${DGREY}·${RESET} ${GREY}${used_fmt}/${window_fmt}${RESET}"
echo "${LGREY}[${RESET}${bar_color}${bar_fill}${RESET}${bar_empty}${LGREY}]${RESET} ${bar_color}${pct}%${RESET}${rate_str}"
