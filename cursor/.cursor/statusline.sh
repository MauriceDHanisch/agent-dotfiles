#!/bin/bash
# Cursor-themed CLI status line.
# Sparse accents only: >_ , ◈ title, 📁 path.
# Payload dump: ~/.cursor/statusline.last.json
data=$(cat)
printf '%s' "$data" >"$HOME/.cursor/statusline.last.json" 2>/dev/null || true

# --- parse ---
raw_model=$(echo "$data" | jq -r '.model.display_name // "Cursor"')
model_id=$(echo "$data" | jq -r '.model.id // empty')
model=$(printf '%s' "$raw_model" | sed 's/ (.*)//')
param_summary=$(echo "$data" | jq -r '.model.param_summary // empty')
max_mode=$(echo "$data" | jq -r '.model.max_mode // false')
cwd=$(echo "$data" | jq -r '.workspace.current_dir // .cwd // "."')
directory=$(basename "$cwd")
worktree=$(echo "$data" | jq -r '.worktree.name // empty')
[ -n "$worktree" ] && directory="wt:$worktree"
session_name=$(echo "$data" | jq -r '.session_name // empty')
autorun=$(echo "$data" | jq -r '.autorun // false')
pct=$(echo "$data" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
rem=$(echo "$data" | jq -r '.context_window.remaining_percentage // empty' | cut -d. -f1)
window_size=$(echo "$data" | jq -r '.context_window.context_window_size // 0')
in_tokens=$(echo "$data" | jq -r '.context_window.total_input_tokens // 0')
out_tokens=$(echo "$data" | jq -r '.context_window.total_output_tokens // 0')
turn_in=$(echo "$data" | jq -r '.context_window.current_usage.input_tokens // 0')
turn_out=$(echo "$data" | jq -r '.context_window.current_usage.output_tokens // 0')
cache_read=$(echo "$data" | jq -r '.context_window.current_usage.cache_read_input_tokens // 0')
cache_write=$(echo "$data" | jq -r '.context_window.current_usage.cache_creation_input_tokens // 0')
five_h=$(echo "$data" | jq -r '.rate_limits.five_hour.used_percentage // empty' | cut -d. -f1)
seven_d=$(echo "$data" | jq -r '.rate_limits.seven_day.used_percentage // empty' | cut -d. -f1)

for v in pct rem window_size in_tokens out_tokens turn_in turn_out cache_read cache_write; do
  eval "case \"\$$v\" in ''|null) $v=0 ;; esac"
done
used_tokens=$((in_tokens + out_tokens))

# --- colors ---
CARET=$'\e[1;38;2;120;220;200m'
TITLE=$'\e[1;38;2;120;220;200m'
MODEL=$'\e[1;38;2;245;245;245m'
DIM=$'\e[38;2;100;100;100m'
SOFT=$'\e[38;2;165;165;165m'
WHITE=$'\e[1;38;2;230;230;230m'
CYAN=$'\e[38;2;120;200;220m'
YELL=$'\e[38;2;220;190;90m'
ORNG=$'\e[38;2;230;140;70m'
RED=$'\e[38;2;220;90;90m'
GRN=$'\e[38;2;110;200;130m'
RESET=$'\e[0m'
SEP="${DIM}  |  ${RESET}"

fmt_tokens() {
  local n=$1
  if [ "$n" -ge 1000000 ]; then
    printf "%.1fM" "$(echo "$n / 1000000" | bc -l)"
  elif [ "$n" -ge 1000 ]; then
    printf "%.1fk" "$(echo "$n / 1000" | bc -l)"
  else
    echo "$n"
  fi
}

join_pipe() {
  local out="" part
  for part in "$@"; do
    [ -z "$part" ] && continue
    if [ -z "$out" ]; then
      out="$part"
    else
      out="${out}${SEP}${part}"
    fi
  done
  printf '%s' "$out"
}

branch=$(git -C "$cwd" branch --show-current 2>/dev/null || echo "")
dirty=""
if [ -n "$branch" ]; then
  if ! git -C "$cwd" diff --quiet 2>/dev/null || ! git -C "$cwd" diff --cached --quiet 2>/dev/null; then
    dirty="*"
  fi
fi

used_fmt=$(fmt_tokens "$used_tokens")
window_fmt=$(fmt_tokens "$window_size")
tin_fmt=$(fmt_tokens "$turn_in")
tout_fmt=$(fmt_tokens "$turn_out")

cache_pct=0
cache_denom=$((cache_read + turn_in))
[ "$cache_denom" -gt 0 ] && cache_pct=$((cache_read * 100 / cache_denom))

if [ "$pct" -lt 50 ]; then
  bar_c=$GRN
elif [ "$pct" -lt 75 ]; then
  bar_c=$YELL
elif [ "$pct" -lt 90 ]; then
  bar_c=$ORNG
else
  bar_c=$RED
fi

filled=$((pct * 16 / 100))
[ "$filled" -gt 16 ] && filled=16
[ "$filled" -lt 0 ] && filled=0
empty=$((16 - filled))
bar_fill=""
bar_empty=""
i=0
while [ "$i" -lt "$filled" ]; do bar_fill="${bar_fill}━"; i=$((i + 1)); done
i=0
while [ "$i" -lt "$empty" ]; do bar_empty="${bar_empty}─"; i=$((i + 1)); done

thinking=false
effort=""
if [ -n "$param_summary" ] && [ "$param_summary" != "null" ]; then
  cleaned=$(printf '%s' "$param_summary" | sed 's/[()]//g; s/^[[:space:]]*//; s/[[:space:]]*$//')
  case "$cleaned" in
    *[Tt]hink*)
      thinking=true
      effort=$(printf '%s' "$cleaned" | sed -E 's/[Tt]hinking//g; s/[·•|,]+/ /g; s/[[:space:]]+/ /g; s/^[[:space:]]*//; s/[[:space:]]*$//')
      ;;
    *) effort="$cleaned" ;;
  esac
fi
case "$raw_model $model_id" in *[Tt]hink*) thinking=true ;; esac

model_bits="${MODEL}${model}${RESET}"
[ "$thinking" = "true" ] && model_bits="${model_bits} ${DIM}/${RESET} ${CYAN}think${RESET}"
[ -n "$effort" ] && model_bits="${model_bits} ${DIM}/${RESET} ${SOFT}${effort}${RESET}"
[ "$max_mode" = "true" ] && model_bits="${model_bits} ${DIM}/${RESET} ${YELL}max${RESET}"

# Prefer live payload, then cli-config approvalMode.
approval_mode=$(echo "$data" | jq -r '.approvalMode // empty')
if [ -z "$approval_mode" ] || [ "$approval_mode" = "null" ]; then
  approval_mode=$(jq -r '.approvalMode // empty' "$HOME/.cursor/cli-config.json" 2>/dev/null || true)
fi
case "$approval_mode" in
  auto-review|auto_review|smart-auto)
    mode_bit="${CYAN}auto-review${RESET}"
    ;;
  unrestricted|yolo|run-everything)
    mode_bit="${ORNG}unrestricted${RESET}"
    ;;
  allowlist)
    mode_bit="${SOFT}allowlist${RESET}"
    ;;
  *)
    if [ "$autorun" = "true" ]; then
      mode_bit="${ORNG}autorun${RESET}"
    else
      mode_bit="${SOFT}prompt${RESET}"
    fi
    ;;
esac
# Session autorun / --force overrides persisted allowlist label.
if [ "$autorun" = "true" ] && [ "$approval_mode" != "auto-review" ] && [ "$approval_mode" != "auto_review" ]; then
  mode_bit="${ORNG}unrestricted${RESET}"
fi

title_bit=""
if [ -n "$session_name" ] && [ "$session_name" != "New Agent" ] && [ "$session_name" != "null" ]; then
  title_bit="${TITLE}◈ $(printf '%s' "$session_name" | cut -c1-36)${RESET}"
fi

loc="${CARET}📁${RESET} ${WHITE}${directory}${RESET}"
[ -n "$branch" ] && loc="${loc} ${DIM}@${RESET} ${SOFT}${branch}${dirty}${RESET}"

ctx_bit="${DIM}[${RESET}${bar_c}${bar_fill}${RESET}${DIM}${bar_empty}]${RESET}  ${bar_c}${pct}%${RESET} ${DIM}·${RESET} ${SOFT}${used_fmt}/${window_fmt}${RESET}"

last_bit=""
if [ "$turn_in" -gt 0 ] || [ "$turn_out" -gt 0 ]; then
  last_bit="${SOFT}LAST:${RESET} ${SOFT}↑ ${tin_fmt}${RESET}"
  if [ "$cache_denom" -gt 0 ]; then
    if [ "$cache_pct" -ge 70 ]; then
      cc=$GRN
    elif [ "$cache_pct" -ge 30 ]; then
      cc=$YELL
    else
      cc=$ORNG
    fi
    last_bit="${last_bit} ${DIM}(${RESET}${cc}${cache_pct}% cached${RESET}${DIM})${RESET}"
  fi
  last_bit="${last_bit} ${SOFT}↓ ${tout_fmt}${RESET}"
fi

rate_bit=""
[ -n "$five_h" ] && [ "$five_h" != "empty" ] && [ "$five_h" != "null" ] && \
  rate_bit="${SOFT}5h ${five_h}%${RESET}"
seven_bit=""
[ -n "$seven_d" ] && [ "$seven_d" != "empty" ] && [ "$seven_d" != "null" ] && \
  seven_bit="${SOFT}7d ${seven_d}%${RESET}"

stats=$(join_pipe "$ctx_bit" "$last_bit" "$rate_bit" "$seven_bit")

# Line 1: caret + model/effort + path + mode + title
line1="${CARET}>_${RESET} ${model_bits}${SEP}${loc}${SEP}${mode_bit}"
[ -n "$title_bit" ] && line1="${line1}${SEP}${title_bit}"

printf '%s\n' "$line1"
printf '%s\n' "${stats}"
