#!/usr/bin/env bash
# Agent Dotfiles installer.
#
#   curl -fsSL https://raw.githubusercontent.com/MauriceDHanisch/agent-dotfiles/main/setup.sh | bash
#
# Clones/updates ~/.agent-dotfiles and symlinks each agent's config into $HOME.
# With no arguments on an interactive terminal it prompts for which components
# to install (default: all). Pass names to skip the prompt:
#
#   curl -fsSL .../setup.sh | bash -s -- claude skills
set -eo pipefail

REPO_URL="${AGENT_DOTFILES_REPO:-https://github.com/MauriceDHanisch/agent-dotfiles.git}"
TARGET_DIR="$HOME/.agent-dotfiles"
BACKUP_DIR="$HOME/.agent-dotfiles-backup/$(date +%Y%m%d-%H%M%S)"
ALL_COMPONENTS="claude gemini antigravity codex skills"

# ---- styling (scoop-watch palette) ---------------------------------------
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    B=$'\e[1m'; D=$'\e[2m'; G=$'\e[38;5;114m'; C=$'\e[38;5;110m'; R=$'\e[31m'; X=$'\e[0m'
else
    B=""; D=""; G=""; C=""; R=""; X=""
fi
step() { printf '\n%s→%s %s\n' "$C" "$X" "$*"; }
ok()   { printf '  %s✓%s %s\n' "$G" "$X" "$*"; }
warn() { printf '  %s•%s %s\n' "$C" "$X" "$*"; }
die()  { printf '  %s✗%s %s\n' "$R" "$X" "$*" >&2; exit 1; }

desc_of() {
    case "$1" in
        claude)      echo "Claude Code     ~/.claude" ;;
        gemini)      echo "Gemini CLI      ~/.gemini" ;;
        antigravity) echo "Antigravity     ~/.gemini/antigravity-cli" ;;
        codex)       echo "Codex           ~/.codex" ;;
        skills)      echo "Shared skills   ~/.agents/skills" ;;
    esac
}

printf '\n%sagent-dotfiles%s %sinstaller%s\n' "$B" "$X" "$D" "$X"
printf '%s───────────────────────%s\n' "$D" "$X"

command -v git >/dev/null 2>&1 || die "git is required but not found"

# ---- 1. select components ------------------------------------------------
# Args win (non-interactive). Otherwise prompt on a real terminal; fall back
# to all when there is no TTY (CI, piped without /dev/tty).
COMPONENTS="$*"
if [ -z "$COMPONENTS" ]; then
    if [ -r /dev/tty ] && [ -z "${CI:-}" ] && [ -z "${NONINTERACTIVE:-}" ]; then
        step "Select components"
        i=1
        for c in $ALL_COMPONENTS; do
            printf '  %s[%d]%s %s%-12s%s %s%s%s\n' "$C" "$i" "$X" "$B" "$c" "$X" "$D" "$(desc_of "$c")" "$X"
            i=$((i + 1))
        done
        printf '\n  %snumbers or names (space/comma separated), or Enter for all%s\n  %s> %s' "$D" "$X" "$C" "$X"
        reply=""
        read -r reply < /dev/tty || reply=""

        if [ -z "$reply" ] || [ "$reply" = "all" ]; then
            COMPONENTS="$ALL_COMPONENTS"
        else
            reply="${reply//,/ }"
            COMPONENTS=""
            for tok in $reply; do
                case "$tok" in
                    1) COMPONENTS="$COMPONENTS claude" ;;
                    2) COMPONENTS="$COMPONENTS gemini" ;;
                    3) COMPONENTS="$COMPONENTS antigravity" ;;
                    4) COMPONENTS="$COMPONENTS codex" ;;
                    5) COMPONENTS="$COMPONENTS skills" ;;
                    claude|gemini|antigravity|codex|skills) COMPONENTS="$COMPONENTS $tok" ;;
                    *) warn "ignoring unknown selection: $tok" ;;
                esac
            done
            [ -z "${COMPONENTS// /}" ] && COMPONENTS="$ALL_COMPONENTS"
        fi
        ok "selected:$(printf ' %s' $COMPONENTS)"
    else
        COMPONENTS="$ALL_COMPONENTS"
    fi
fi

# ---- 2. clone / update ---------------------------------------------------
# The repo mirrors upstream; plain `git pull` breaks on force-pushes, so we
# hard-reset to origin/main and report the diff explicitly.
step "Repository"
repo_files_changed=0
final_word="synced"
if [ ! -d "$TARGET_DIR" ]; then
    git clone --quiet "$REPO_URL" "$TARGET_DIR"
    cd "$TARGET_DIR"
    final_word="installed"
    ok "cloned ${D}@ $(git rev-parse --short HEAD)${X}"
else
    cd "$TARGET_DIR"
    before="$(git rev-parse HEAD 2>/dev/null || echo '')"
    git fetch --quiet origin
    git reset --quiet --hard origin/main
    after="$(git rev-parse HEAD)"
    if [ "$before" = "$after" ]; then
        final_word="up to date"
        ok "already up to date ${D}@ $(git rev-parse --short HEAD)${X}"
    else
        final_word="updated"
        repo_files_changed="$(git diff --name-only "$before" "$after" | wc -l | tr -d ' ')"
        ok "updated ${D}$(git rev-parse --short "$before") → $(git rev-parse --short "$after")${X} (${repo_files_changed} file(s) changed)"
        git diff --name-status "$before" "$after" | while IFS=$'\t' read -r status path _; do
            printf '      %s%-2s%s %s%s%s\n' "$C" "$status" "$X" "$D" "$path" "$X"
        done
    fi
fi

# Remove any broken-symlink ancestors of $1 so mkdir -p can rebuild the path.
clear_broken_ancestors() {
    local p="$1"
    while [ "$p" != "$HOME" ] && [ "$p" != "/" ] && [ -n "$p" ]; do
        p="$(dirname "$p")"
        if [ -L "$p" ] && [ ! -e "$p" ]; then
            rm "$p"
        fi
    done
}

TOT_LINKED=0; TOT_BACKED=0; TOT_ORPHAN=0; TOT_OK=0

# install_component <package-name>
#
# The repo is the source of truth: for every tracked file we ensure
# $HOME/<rel> is a symlink to the repo file. Orphan symlinks pointing into the
# repo whose target vanished are removed. Local-only files are never touched.
install_component() {
    local pkg="$1"
    local pkg_dir="$TARGET_DIR/$pkg"

    if [ ! -d "$pkg_dir" ]; then
        warn "${B}${pkg}${X} not found, skipping"
        return
    fi

    local linked=0 backed_up=0 skipped=0
    while IFS= read -r src; do
        local rel="${src#$pkg_dir/}"
        local dst="$HOME/$rel"

        # Already the correct symlink? Leave it.
        if [ -L "$dst" ] && [ -e "$dst" ]; then
            local current
            current="$(readlink "$dst")"
            if [ "$current" = "$src" ]; then
                skipped=$((skipped + 1)); continue
            fi
            local resolved
            resolved="$(readlink -f "$dst" 2>/dev/null || true)"
            if [ "$resolved" = "$src" ]; then
                skipped=$((skipped + 1)); continue
            fi
        fi

        # A real file living inside the repo via an already-symlinked ancestor?
        if [ -e "$dst" ] && [ ! -L "$dst" ]; then
            local real
            real="$(cd "$(dirname "$dst")" 2>/dev/null && pwd -P)/$(basename "$dst")"
            case "$real" in
                "$TARGET_DIR"/*) skipped=$((skipped + 1)); continue ;;
            esac
        fi

        # Anything still here (real file, wrong/broken symlink) needs to move.
        if [ -e "$dst" ] || [ -L "$dst" ]; then
            local backup_path="$BACKUP_DIR/$rel"
            clear_broken_ancestors "$backup_path"
            mkdir -p "$(dirname "$backup_path")"
            mv "$dst" "$backup_path"
            printf '      %s· backup %s → %s%s\n' "$D" "$dst" "$backup_path" "$X"
            backed_up=$((backed_up + 1))
        fi

        clear_broken_ancestors "$dst"
        mkdir -p "$(dirname "$dst")"
        ln -s "$src" "$dst"
        linked=$((linked + 1))
    done < <(find "$pkg_dir" \( -type f -o -type l \) ! -path '*/.git/*')

    # Orphan cleanup.
    local top_dir target_root orphans=0
    top_dir="$(basename "$(find "$pkg_dir" -mindepth 1 -maxdepth 1 -type d | head -1)")"
    target_root="$HOME/$top_dir"
    if [ -d "$target_root" ]; then
        while IFS= read -r link; do
            local lnk_target
            lnk_target="$(readlink "$link")"
            case "$lnk_target" in
                /*) ;;
                *) lnk_target="$(cd "$(dirname "$link")" 2>/dev/null && pwd -P)/$lnk_target" ;;
            esac
            case "$lnk_target" in
                "$TARGET_DIR"/*) ;;
                *) continue ;;
            esac
            if [ ! -e "$lnk_target" ]; then
                rm "$link"
                printf '      %s· orphan removed %s%s\n' "$D" "$link" "$X"
                orphans=$((orphans + 1))
            fi
        done < <(find "$target_root" -type l 2>/dev/null)
    fi

    TOT_LINKED=$((TOT_LINKED + linked))
    TOT_BACKED=$((TOT_BACKED + backed_up))
    TOT_ORPHAN=$((TOT_ORPHAN + orphans))
    TOT_OK=$((TOT_OK + skipped))

    # Mention only what actually happened.
    local detail parts=()
    [ "$linked" -gt 0 ]    && parts+=("${G}${linked} linked${X}")
    [ "$backed_up" -gt 0 ] && parts+=("${C}${backed_up} backed up${X}")
    [ "$orphans" -gt 0 ]   && parts+=("${C}${orphans} removed${X}")
    [ "$skipped" -gt 0 ]   && parts+=("${D}${skipped} ok${X}")
    if [ ${#parts[@]} -eq 0 ]; then
        detail="${D}nothing to do${X}"
    else
        local IFS=", "; detail="${parts[*]}"
    fi
    printf '  %s✓%s %s%-12s%s %s\n' "$G" "$X" "$B" "$pkg" "$X" "$detail"
}

# ---- 3. install ----------------------------------------------------------
step "Components"
for COMPONENT in $COMPONENTS; do
    case $COMPONENT in
        claude|gemini|antigravity|codex|skills) install_component "$COMPONENT" ;;
        *) warn "${B}${COMPONENT}${X} unknown, skipping" ;;
    esac
done

# ---- 4. summary ----------------------------------------------------------
printf '\n%s%s✓%s %sagent-dotfiles %s%s\n' "$B" "$G" "$X" "$B" "$final_word" "$X"
printf '  %s%s repo file(s) updated · %s linked · %s backed up · %s orphan(s) removed · %s unchanged%s\n' \
    "$D" "$repo_files_changed" "$TOT_LINKED" "$TOT_BACKED" "$TOT_ORPHAN" "$TOT_OK" "$X"
if [ -d "$BACKUP_DIR" ]; then
    printf '  %sconflicting files moved to %s%s\n' "$D" "$BACKUP_DIR" "$X"
fi
printf '  %slocal-only files (history, credentials, sessions) preserved%s\n' "$D" "$X"
printf '  %sinstall a subset:%s curl -fsSL .../setup.sh | bash -s -- claude skills\n\n' "$D" "$X"
