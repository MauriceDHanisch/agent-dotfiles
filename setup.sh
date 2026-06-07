#!/bin/bash
set -e

REPO_URL="https://github.com/MauriceDHanisch/agent-dotfiles.git"
TARGET_DIR="$HOME/.agent-dotfiles"
BACKUP_DIR="$HOME/.agent-dotfiles-backup/$(date +%Y%m%d-%H%M%S)"

# ---- styling -------------------------------------------------------------
# Color only when stdout is a terminal and NO_COLOR is unset. With
# `curl ... | bash`, stdout is still the terminal, so colors render fine.
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    BOLD=$'\033[1m'; DIM=$'\033[2m'; RESET=$'\033[0m'
    GREEN=$'\033[32m'; YELLOW=$'\033[33m'; BLUE=$'\033[34m'; CYAN=$'\033[36m'; RED=$'\033[31m'
else
    BOLD=""; DIM=""; RESET=""; GREEN=""; YELLOW=""; BLUE=""; CYAN=""; RED=""
fi

hr() { printf "%s────────────────────────────────────────────────────%s\n" "$DIM" "$RESET"; }
section() { printf "\n%s▸ %s%s\n" "$BOLD" "$1" "$RESET"; }

printf "\n%sAI Agent Dotfiles%s  %s· %s%s\n" "$BOLD" "$RESET" "$DIM" "$TARGET_DIR" "$RESET"
hr

# ---- 1. clone / update ---------------------------------------------------
# The repo is a mirror of upstream; plain `git pull` breaks on force-pushes,
# so we hard-reset to origin/main and report the diff explicitly.
section "Repository"
repo_files_changed=0
if [ ! -d "$TARGET_DIR" ]; then
    git clone --quiet "$REPO_URL" "$TARGET_DIR"
    cd "$TARGET_DIR"
    after="$(git rev-parse --short HEAD)"
    printf "  %scloned%s  %s@ %s%s\n" "$GREEN" "$RESET" "$DIM" "$after" "$RESET"
else
    cd "$TARGET_DIR"
    before="$(git rev-parse HEAD 2>/dev/null || echo '')"
    git fetch --quiet origin
    git reset --quiet --hard origin/main
    after="$(git rev-parse HEAD)"

    if [ "$before" = "$after" ]; then
        printf "  %salready up to date%s  %s@ %s%s\n" \
            "$DIM" "$RESET" "$DIM" "$(git rev-parse --short HEAD)" "$RESET"
    else
        repo_files_changed="$(git diff --name-only "$before" "$after" | wc -l | tr -d ' ')"
        printf "  %supdated%s  %s%s → %s%s  %s(%s file(s) changed)%s\n" \
            "$GREEN" "$RESET" \
            "$DIM" "$(git rev-parse --short "$before")" "$(git rev-parse --short "$after")" "$RESET" \
            "$DIM" "$repo_files_changed" "$RESET"
        git diff --name-status "$before" "$after" | while IFS=$'\t' read -r status path _; do
            printf "      %s%-2s%s %s%s%s\n" "$CYAN" "$status" "$RESET" "$DIM" "$path" "$RESET"
        done
    fi
fi

# ---- 2. select components ------------------------------------------------
COMPONENTS=("$@")
if [ ${#COMPONENTS[@]} -eq 0 ]; then
    COMPONENTS=("claude" "gemini" "antigravity" "codex" "skills")
fi

# Remove any broken-symlink ancestors of $1 (so mkdir -p can create real
# directories along the path). Walks up to $HOME.
clear_broken_ancestors() {
    local p="$1"
    while [ "$p" != "$HOME" ] && [ "$p" != "/" ] && [ -n "$p" ]; do
        p="$(dirname "$p")"
        if [ -L "$p" ] && [ ! -e "$p" ]; then
            rm "$p"
        fi
    done
}

# Totals across all components.
TOT_LINKED=0; TOT_BACKED=0; TOT_ORPHAN=0; TOT_OK=0

# install_component <package-name>
#
# The repo is the source of truth. For every file tracked in the package we
# ensure $HOME/<rel> is a symlink to the repo file. After linking, removes any
# orphan symlinks under the package's target tree that point into the repo but
# whose target no longer exists. Files that exist only locally (history,
# credentials, sessions, sqlite dbs, ...) are never touched.
install_component() {
    local pkg="$1"
    local pkg_dir="$TARGET_DIR/$pkg"

    if [ ! -d "$pkg_dir" ]; then
        printf "  %s%-12s%s %snot found, skipping%s\n" "$BOLD" "$pkg" "$RESET" "$YELLOW" "$RESET"
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

        # A regular file (or dir) that lives inside the repo because an
        # ancestor was already symlinked? Skip — it's already correct.
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
            printf "      %s· backup %s → %s%s\n" "$DIM" "$dst" "$backup_path" "$RESET"
            backed_up=$((backed_up + 1))
        fi

        clear_broken_ancestors "$dst"
        mkdir -p "$(dirname "$dst")"
        ln -s "$src" "$dst"
        linked=$((linked + 1))
    done < <(find "$pkg_dir" \( -type f -o -type l \) ! -path '*/.git/*')

    # Orphan cleanup
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
                printf "      %s· orphan removed %s%s\n" "$DIM" "$link" "$RESET"
                orphans=$((orphans + 1))
            fi
        done < <(find "$target_root" -type l 2>/dev/null)
    fi

    TOT_LINKED=$((TOT_LINKED + linked))
    TOT_BACKED=$((TOT_BACKED + backed_up))
    TOT_ORPHAN=$((TOT_ORPHAN + orphans))
    TOT_OK=$((TOT_OK + skipped))

    # Build a detail string mentioning only what actually happened.
    local detail parts=()
    [ "$linked" -gt 0 ]    && parts+=("${GREEN}${linked} linked${RESET}")
    [ "$backed_up" -gt 0 ] && parts+=("${YELLOW}${backed_up} backed up${RESET}")
    [ "$orphans" -gt 0 ]   && parts+=("${YELLOW}${orphans} removed${RESET}")
    [ "$skipped" -gt 0 ]   && parts+=("${DIM}${skipped} ok${RESET}")
    if [ ${#parts[@]} -eq 0 ]; then
        detail="${DIM}nothing to do${RESET}"
    else
        local IFS=", "; detail="${parts[*]}"
    fi
    printf "  %s%-12s%s %s\n" "$BOLD" "$pkg" "$RESET" "$detail"
}

# ---- 3. install ----------------------------------------------------------
section "Components"
for COMPONENT in "${COMPONENTS[@]}"; do
    case $COMPONENT in
        claude|gemini|antigravity|codex|skills) install_component "$COMPONENT" ;;
        *) printf "  %s%-12s%s %sunknown, skipping%s\n" "$BOLD" "$COMPONENT" "$RESET" "$YELLOW" "$RESET" ;;
    esac
done

# ---- 4. summary ----------------------------------------------------------
hr
printf "%s✓ Complete%s  %s%s repo file(s) updated · %s linked · %s backed up · %s orphan(s) removed · %s unchanged%s\n" \
    "$GREEN" "$RESET" "$DIM" "$repo_files_changed" "$TOT_LINKED" "$TOT_BACKED" "$TOT_ORPHAN" "$TOT_OK" "$RESET"

if [ -d "$BACKUP_DIR" ]; then
    printf "%s  conflicting files moved to %s%s\n" "$DIM" "$BACKUP_DIR" "$RESET"
fi
printf "%s  local-only files (history, credentials, sessions) were preserved%s\n" "$DIM" "$RESET"
printf "%s  install a subset:%s bash setup.sh claude skills\n\n" "$DIM" "$RESET"
