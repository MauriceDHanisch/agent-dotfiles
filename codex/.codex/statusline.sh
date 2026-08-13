#!/usr/bin/env bash

# Native Codex status surface. Codex supplies JSON on stdin once per second.
set -o pipefail

data=$(cat)

json() {
    jq -r "$1" <<<"$data" 2>/dev/null
}

format_tokens() {
    local value=${1:-0}
    if ((value >= 1000000)); then
        awk -v n="$value" 'BEGIN { printf "%.1fM", n / 1000000 }'
    elif ((value >= 1000)); then
        awk -v n="$value" 'BEGIN { printf "%.1fk", n / 1000 }'
    else
        printf '%s' "$value"
    fi
}

relative_time() {
    local reset=${1:-}
    local now seconds minutes hours days
    [[ "$reset" =~ ^[0-9]+$ ]] || return
    now=$(date +%s)
    seconds=$((reset - now))
    ((seconds > 0)) || return
    minutes=$((seconds / 60))
    hours=$((minutes / 60))
    days=$((hours / 24))
    if ((days > 0)); then
        printf '%dd %dh' "$days" "$((hours % 24))"
    elif ((hours > 0)); then
        printf '%dh %dm' "$hours" "$((minutes % 60))"
    else
        printf '%dm' "$minutes"
    fi
}

weekly_reset_time() {
    local reset=${1:-}
    [[ "$reset" =~ ^[0-9]+$ ]] || return
    if [[ "$(uname)" == "Darwin" ]]; then
        date -r "$reset" '+%a %H:%M' 2>/dev/null
    else
        date -d "@$reset" '+%a %H:%M' 2>/dev/null
    fi
}

bar() {
    local percent=${1:-0}
    local width=10 filled empty
    filled=$(((percent * width + 50) / 100))
    empty=$((width - filled))
    ((filled > 0)) && printf '%s' "$context_color"
    ((filled > 0)) && printf '●%.0s' $(seq 1 "$filled")
    ((empty > 0)) && printf '%s' "${DIM}${MUTED}"
    ((empty > 0)) && printf '○%.0s' $(seq 1 "$empty")
    printf '%s' "$RESET"
}

rate_color() {
    local percent=${1:-0}
    if ((percent >= 90)); then
        printf '%s' "$RED"
    elif ((percent >= 70)); then
        printf '%s' "$YELLOW"
    else
        printf '%s' "$CYAN"
    fi
}

approval_color() {
    case "$1" in
        "ask for approval") printf '%s' "$GREEN" ;;
        "approve for me") printf '%s' "$YELLOW" ;;
        "unless trusted") printf '%s' "$CYAN" ;;
        never) printf '%s' "$RED" ;;
        "") printf '%s' "$MUTED" ;;
        *) printf '%s' "$MAGENTA" ;;
    esac
}

agent_state_color() {
    case "$1" in
        ready) printf '%s' "$GREEN" ;;
        working) printf '%s' "$CYAN" ;;
        thinking) printf '%s' "$MAGENTA" ;;
        waiting) printf '%s' "$YELLOW" ;;
        starting) printf '%s' "$BLUE" ;;
        *) printf '%s' "$MUTED" ;;
    esac
}

model=$(json '.model.display_name // "Codex"')
effort=$(json '.effort.level // "none"')
fast_mode=$(json '.service_tier.fast_enabled // false')
conversation_kind=$(json '.conversation.kind // "main"')
active_agents=$(json '.conversation.active_agents // 0')
stopped_agents=$(json '.conversation.stopped_agents // 0')
agent_label=$(json '.conversation.agent_label // empty')
cwd=$(json '.workspace.current_dir // "."')
project=$(basename "$cwd")
agent_state=$(json '.agent_state // "idle"')
approval_mode=$(json '.approval_mode // ""')
agent_state=$(printf '%s' "$agent_state" | tr '[:upper:]' '[:lower:]')
approval_mode=$(printf '%s' "$approval_mode" | tr '[:upper:]' '[:lower:]')

context_pct=$(json '.context_window.used_percentage // 0')
context_size=$(json '.context_window.context_window_size // 0')
context_used=$(json '.context_window.used_tokens // 0')

last_input=$(json '.last_turn.input_tokens // 0')
last_cached=$(json '.last_turn.cached_input_tokens // 0')
last_output=$(json '.last_turn.output_tokens // 0')
last_reasoning=$(json '.last_turn.reasoning_output_tokens // 0')
cache_pct=0
if ((last_input > 0)); then
    cache_pct=$((last_cached * 100 / last_input))
fi

five_hour=$(json '.rate_limits.five_hour.used_percentage // 0' | cut -d. -f1)
five_hour_reset=$(json '.rate_limits.five_hour.resets_at // empty')
seven_day=$(json '.rate_limits.seven_day.used_percentage // 0' | cut -d. -f1)
seven_day_reset=$(json '.rate_limits.seven_day.resets_at // empty')

RESET=$'\e[0m'
DIM=$'\e[2;38;2;135;145;165m'
WHITE=$'\e[38;2;225;232;245m'
MUTED=$'\e[38;2;165;175;195m'
CYAN=$'\e[38;2;110;190;230m'
BLUE=$'\e[38;2;120;150;255m'
GREEN=$'\e[38;2;110;210;155m'
YELLOW=$'\e[38;2;235;190;95m'
RED=$'\e[38;2;235;110;115m'
MAGENTA=$'\e[38;2;225;180;245m'
LIMITS=$'\e[38;2;200;140;155m'

branch=''
git_summary=''
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    branch=$(git branch --show-current 2>/dev/null)
    porcelain=$(git status --porcelain=v1 2>/dev/null)
    modified=$(awk 'substr($0, 1, 2) ~ /M/ { count++ } END { print count + 0 }' <<<"$porcelain")
    added=$(awk 'substr($0, 1, 2) ~ /A/ { count++ } END { print count + 0 }' <<<"$porcelain")
    untracked=$(awk 'substr($0, 1, 2) == "??" { count++ } END { print count + 0 }' <<<"$porcelain")
    [[ -n "$branch" ]] && git_summary="${BLUE}${branch}${RESET}"
    ((added > 0)) && git_summary+=" ${GREEN}+${added}${RESET}"
    ((modified > 0)) && git_summary+=" ${YELLOW}~${modified}${RESET}"
    ((untracked > 0)) && git_summary+=" ${RED}?${untracked}${RESET}"
fi

context_color=$GREEN
if ((context_pct >= 75)); then
    context_color=$RED
elif ((context_pct >= 50)); then
    context_color=$YELLOW
fi
last_turn=''
if ((last_input > 0 || last_output > 0)); then
    last_turn="${CYAN}↑ $(format_tokens "$last_input")${RESET}"
    if ((last_cached > 0)); then
        last_turn+=" ${DIM}${CYAN}(${cache_pct}% cached)${RESET}"
    fi
    last_turn+=" ${BLUE}↓ $(format_tokens "$last_output")${RESET}"
    if ((last_reasoning > 0)); then
        last_turn+=" ${DIM}${BLUE}r:$(format_tokens "$last_reasoning")${RESET}"
    fi
fi

five_reset=$(relative_time "$five_hour_reset")
seven_reset=$(weekly_reset_time "$seven_day_reset")
five_hour_status=''
if ((five_hour > 0)); then
    five_hour_status="${LIMITS}5h ${five_hour}%${RESET}${five_reset:+ ${DIM}${LIMITS}(${five_reset})${RESET}} ${DIM}│${RESET} "
fi
fast_status=" ${MUTED}○ fast off${RESET}"
if [[ "$fast_mode" == "true" ]]; then
    fast_status=" ${YELLOW}ϟ fast on${RESET}"
fi
conversation_status=''
case "$conversation_kind" in
    main) conversation_status=" ${DIM}│${RESET} ${MAGENTA}agents: ◆ ${active_agents}  ◇ ${stopped_agents}${RESET}" ;;
    side) conversation_status=" ${DIM}│${RESET} ${MAGENTA}/btw${RESET}" ;;
    agent) [[ -n "$agent_label" ]] && conversation_status=" ${DIM}│${RESET} ${MAGENTA}agent: ${agent_label}${RESET}" ;;
esac
echo
echo "${CYAN}[${model}]${RESET} ${MUTED}⚙ ${effort}${RESET}${fast_status} ${DIM}│${RESET} ${GREEN}>_${RESET} ${WHITE}${project}${RESET}${git_summary:+ ${DIM}│${RESET} ${BLUE}⎇${RESET} ${git_summary}}"
if ((context_size > 0)); then
    echo "${MUTED}◒ context:${RESET} ${context_color}${context_pct}% used${RESET} $(bar "$context_pct") ${MUTED}· $(format_tokens "$context_used") / $(format_tokens "$context_size")${RESET}${last_turn:+ ${DIM}│${RESET} ${MAGENTA}last:${RESET} ${last_turn}}"
else
    echo "${MUTED}◒ context:${RESET} ${DIM}awaiting first turn${RESET}${last_turn:+ ${DIM}│${RESET} ${MAGENTA}last:${RESET} ${last_turn}}"
fi
echo "${LIMITS}◷ limits:${RESET} ${five_hour_status}${LIMITS}7d ${seven_day}%${RESET}${seven_reset:+ ${DIM}${LIMITS}(${seven_reset})${RESET}} ${DIM}│${RESET} $(agent_state_color "$agent_state")● ${agent_state}${RESET}${approval_mode:+ ${DIM}│${RESET} $(approval_color "$approval_mode")◆ ${approval_mode}${RESET}}${conversation_status}"
printf ' \n'
