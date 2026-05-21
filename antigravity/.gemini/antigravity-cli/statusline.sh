#!/bin/bash

data=$(cat)

# Parse JSON with jq
full_model_name=$(echo "$data" | jq -r '.model.display_name // .active_model // "Antigravity"')
model=$(echo "$full_model_name" | sed 's/ (.*)//')
tier_label=$(echo "$data" | jq -r '.model.display_name // .active_model // ""' | sed -n 's/.*(\(.*\)).*/\1/p')
cwd=$(echo "$data" | jq -r '.workspace.current_dir // .cwd // "."')
directory=$(basename "$cwd")
window_size=$(echo "$data" | jq -r '.context_window.context_window_size // 0')
used_tokens=$(echo "$data" | jq -r '(.context_window.total_input_tokens // 0) + (.context_window.total_output_tokens // 0)')
state=$(echo "$data" | jq -r '.agent_state // ""')
tier=$(echo "$data" | jq -r '.plan_tier // ""' | sed 's/Google AI //')
exceeds_200k=$(echo "$data" | jq -r '.exceeds_200k_tokens // false')

# Calculate percentage mathematically from printed token size
if [ "$window_size" -gt 0 ]; then
    pct=$(( (used_tokens * 100 + window_size / 2) / window_size ))
else
    pct=0
fi

# Cache hit calculations
total_in=$(echo "$data" | jq -r '.context_window.total_input_tokens // 0')
cache_read=$(echo "$data" | jq -r '.context_window.current_usage.cache_read_input_tokens // .context_window.cache_read_input_tokens // 0')
if [ "$total_in" -gt 0 ] && [ "$cache_read" -gt 0 ]; then
    cache_pct=$((cache_read * 100 / total_in))
else
    cache_pct=0
fi

# Sandbox Status
sandbox_enabled=$(echo "$data" | jq -r '.sandbox.enabled // false')

# Rate limits / Fuel tank
five_h=$(echo "$data" | jq -r '.rate_limits.five_hour.used_percentage // .fuel_tank.five_hour.used_percentage // empty' | cut -d. -f1)

# Colors - Premium Google Material Dark Palette
M_BLUE=$'\e[38;2;138;180;248m'     # Soft Blue (Material Blue 300)
M_RED=$'\e[38;2;242;139;130m'      # Soft Red (Material Red 300)
M_YELLOW=$'\e[38;2;253;214;99m'    # Soft Yellow (Material Yellow 300)
M_GREEN=$'\e[38;2;129;201;149m'    # Soft Green (Material Green 300)
M_ORANGE=$'\e[38;2;248;169;113m'   # Soft Orange (Material Orange 300)
M_CYAN=$'\e[38;2;128;222;234m'     # Soft Cyan (Material Cyan 300)
WHITE=$'\e[1;37m'
DGREY=$'\e[38;2;120;120;120m'
LGREY=$'\e[38;2;210;210;210m'
RESET=$'\e[0m'

# Dynamic percentage color based on usage heat scale
if [ "$pct" -lt 50 ]; then
    pct_color=$M_GREEN
elif [ "$pct" -lt 75 ]; then
    pct_color=$M_BLUE
elif [ "$pct" -lt 90 ]; then
    pct_color=$M_ORANGE
else
    pct_color=$M_RED
fi

# Git branch
branch=$(git -C "$cwd" branch --show-current 2>/dev/null || echo "")
branch_str=""
[ -n "$branch" ] && branch_str=" ${DGREY}🌿${RESET} ${M_YELLOW}${branch}${RESET}"

# Token window formatting
format_tokens() {
    local n=$1
    if [ "$n" -ge 1000000 ]; then
        echo "$((n / 1000000)).$(((n % 1000000) / 100000))M"
    elif [ "$n" -ge 1000 ]; then
        echo "$((n / 1000))k"
    else
        echo "$n"
    fi
}

used_fmt=$(format_tokens "$used_tokens")
window_fmt=$(format_tokens "$window_size")

# Sandbox text
if [ "$sandbox_enabled" = "true" ]; then
    sandbox_str="🛡️ Sandbox"
else
    sandbox_str="🖥️ Host"
fi

# Thinking state check
has_thinking="false"
if [ "$state" = "thinking" ] || [ "$state" = "reasoning" ] || [ "$(echo "$data" | jq -r '.thinking.enabled // false')" = "true" ]; then
    has_thinking="true"
fi

# --- Segment 1: Model & Brain ---
model_str=""
if [ -n "$tier_label" ]; then
    model_str="${M_BLUE}[${RESET}${WHITE}${model}${RESET} ${M_YELLOW}🧠 ${tier_label}${RESET}${M_BLUE}]${RESET}"
elif [ "$has_thinking" = "true" ]; then
    model_str="${M_BLUE}[${RESET}${WHITE}${model}${RESET} ${M_YELLOW}🧠${RESET}${M_BLUE}]${RESET}"
else
    model_str="${M_BLUE}[${RESET}${WHITE}${model}${RESET}${M_BLUE}]${RESET}"
fi

# --- Segment 2: Workspace & Branch ---
dir_str="${M_GREEN}📁 ${directory}${RESET}${branch_str}"

# --- Segment 3: Context Usage ---
context_str="${pct_color}${pct}%${RESET} ${DGREY}(${used_fmt}/${window_fmt})${RESET}"

# --- Segment 4: Telemetry ---
telemetry_segs=()

# Cache (Cyan)
if [ "$cache_pct" -gt 0 ]; then
    telemetry_segs+=("${M_CYAN}⚡ ${cache_pct}%${RESET}")
fi

# Sandbox (Green)
telemetry_segs+=("${M_GREEN}${sandbox_str}${RESET}")

# 200k Warning (Red)
if [ "$exceeds_200k" = "true" ]; then
    telemetry_segs+=("${M_RED}⚠️ 200k+${RESET}")
fi

# Rate Limit / Tier (Red)
rate_str=""
if [ -n "$five_h" ] && [ "$five_h" != "empty" ]; then
    rate_str="${M_RED}5h:${five_h}%${RESET}"
fi
if [ -z "$rate_str" ] && [ -n "$tier" ]; then
    rate_str="${M_RED}${tier}${RESET}"
fi
if [ -n "$rate_str" ]; then
    telemetry_segs+=("$rate_str")
fi

# Join telemetry segments with " · "
telemetry_str=""
for ((i=0; i<${#telemetry_segs[@]}; i++)); do
    seg=${telemetry_segs[i]}
    if [ $i -eq 0 ]; then
        telemetry_str="${seg}"
    else
        telemetry_str="${telemetry_str} ${DGREY}·${RESET} ${seg}"
    fi
done

# --- Assemble Single Line Output ---
sep=" ${DGREY}╱${RESET} "
line_styled="${model_str}${sep}${dir_str}${sep}${context_str}"
if [ -n "$telemetry_str" ]; then
    line_styled="${line_styled}${sep}${telemetry_str}"
fi

echo "$line_styled"
