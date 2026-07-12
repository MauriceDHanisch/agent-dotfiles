#!/usr/bin/env bash
# Agent Dotfiles installer.
#
#   curl -fsSL https://raw.githubusercontent.com/MauriceDHanisch/agent-dotfiles/main/setup.sh | bash
#
# Clones/updates ~/.agent-dotfiles and symlinks each agent's config into $HOME.
# With no arguments on an interactive terminal it shows a key-driven picker for
# which components to install (default: all selected). Pass names to skip it:
#
#   curl -fsSL .../setup.sh | bash -s -- claude skills
#
# Pass --uninstall to remove the symlinks instead (restoring the most recent
# pre-install backup for each path, if one exists). The repo checkout at
# ~/.agent-dotfiles and any local-only files are left untouched:
#
#   curl -fsSL .../setup.sh | bash -s -- --uninstall
#   curl -fsSL .../setup.sh | bash -s -- --uninstall claude skills
set -eo pipefail

REPO_URL="${AGENT_DOTFILES_REPO:-https://github.com/MauriceDHanisch/agent-dotfiles.git}"
TARGET_DIR="$HOME/.agent-dotfiles"
BACKUP_DIR="$HOME/.agent-dotfiles-backup/$(date +%Y%m%d-%H%M%S)"
ALL_COMPONENTS="claude gemini antigravity codex skills"

MODE="install"
args=()
for a in "$@"; do
    case "$a" in
        --uninstall) MODE="uninstall" ;;
        *) args+=("$a") ;;
    esac
done
set -- "${args[@]}"

# ---- styling -------------------------------------------------------------
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

# ---- interactive multi-select --------------------------------------------
# Arrow keys / j,k move; space toggles; a toggles all; enter confirms; q/esc
# cancels. Reads single keypresses from /dev/tty so it works under curl|bash.
# Result is written to the global SEL_RESULT.
SEL_RESULT=""
menu_select() {
    local opts; opts=($ALL_COMPONENTS)
    local n=${#opts[@]}
    local state=() cur=0 i
    for ((i = 0; i < n; i++)); do state[$i]=1; done   # all selected by default

    printf '  %s↑/↓ or j/k to move · space to toggle · a all · enter to confirm%s\n' "$D" "$X"

    _menu_draw() {
        for ((i = 0; i < n; i++)); do
            local pointer="  " box
            if [ "$i" -eq "$cur" ]; then pointer="${C}❯${X} "; fi
            if [ "${state[$i]}" -eq 1 ]; then box="${G}[x]${X}"; else box="${D}[ ]${X}"; fi
            printf '  %s%s %s%-12s%s %s%s%s\e[K\n' \
                "$pointer" "$box" "$B" "${opts[$i]}" "$X" "$D" "$(desc_of "${opts[$i]}")" "$X"
        done
    }
    _menu_draw

    local key rest v allon
    while true; do
        IFS= read -rsn1 key < /dev/tty || break
        case "$key" in
            $'\e')
                IFS= read -rsn2 -t 1 rest < /dev/tty || rest=""
                case "$rest" in
                    '[A') cur=$(((cur - 1 + n) % n)) ;;
                    '[B') cur=$(((cur + 1) % n)) ;;
                    '')   die "cancelled" ;;
                esac ;;
            k|K) cur=$(((cur - 1 + n) % n)) ;;
            j|J) cur=$(((cur + 1) % n)) ;;
            ' ') state[$cur]=$((1 - ${state[$cur]})) ;;
            a|A)
                allon=1
                for ((i = 0; i < n; i++)); do
                    if [ "${state[$i]}" -eq 0 ]; then allon=0; fi
                done
                if [ "$allon" -eq 1 ]; then v=0; else v=1; fi
                for ((i = 0; i < n; i++)); do state[$i]=$v; done ;;
            q|Q) die "cancelled" ;;
            '')  break ;;   # enter
        esac
        printf '\e[%dA' "$n"   # back to top of the list, redraw in place
        _menu_draw
    done

    SEL_RESULT=""
    for ((i = 0; i < n; i++)); do
        if [ "${state[$i]}" -eq 1 ]; then SEL_RESULT="$SEL_RESULT ${opts[$i]}"; fi
    done
}

if [ "$MODE" = "uninstall" ]; then
    printf '\n%sagent-dotfiles%s %suninstaller%s\n' "$B" "$X" "$D" "$X"
else
    printf '\n%sagent-dotfiles%s %sinstaller%s\n' "$B" "$X" "$D" "$X"
fi
printf '%s───────────────────────%s\n' "$D" "$X"

command -v git >/dev/null 2>&1 || die "git is required but not found"

if [ "$MODE" = "uninstall" ] && [ ! -d "$TARGET_DIR" ]; then
    die "nothing to uninstall, $TARGET_DIR not found"
fi

# ---- 1. select components ------------------------------------------------
# Args win (non-interactive). Otherwise show the picker on a usable TTY; fall
# back to all when there is none (CI, piped without a controlling terminal).
COMPONENTS="$*"
if [ -z "$COMPONENTS" ]; then
    if { true < /dev/tty; } 2>/dev/null && [ -z "${CI:-}" ] && [ -z "${NONINTERACTIVE:-}" ]; then
        step "Select components"
        menu_select
        COMPONENTS="$SEL_RESULT"
        if [ -z "${COMPONENTS// /}" ]; then COMPONENTS="$ALL_COMPONENTS"; fi
        ok "selected:$(printf ' %s' $COMPONENTS)"
    else
        COMPONENTS="$ALL_COMPONENTS"
    fi
fi

# ---- 2. clone / update (install only; uninstall leaves the repo alone) ---
# The repo mirrors upstream; plain `git pull` breaks on force-pushes, so we
# hard-reset to origin/main and report the diff explicitly.
repo_files_changed=0
final_word="synced"
if [ "$MODE" = "uninstall" ]; then
    cd "$TARGET_DIR"
else
    step "Repository"
    if [ ! -d "$TARGET_DIR" ]; then
        git clone --quiet "$REPO_URL" "$TARGET_DIR"
        cd "$TARGET_DIR"
        final_word="installed"
        ok "cloned ${D}@ $(git rev-parse --short HEAD)${X}"
    else
        cd "$TARGET_DIR"
        before="$(git rev-parse HEAD 2>/dev/null || echo '')"
        # Stray untracked files (leftovers from an old copy, a previous script
        # version, etc.) or filesystem quirks on some shared/HPC mounts can
        # make reset --hard fail with "unable to create file X: File exists".
        # git clean (which respects .gitignore, so credentials/history/
        # sessions/cache are untouched) handles the common case; if the sync
        # still fails for any reason, fall back to a full re-clone, since this
        # directory is a disposable mirror of upstream, never a place for
        # local work.
        if git fetch --quiet origin 2>/dev/null \
            && git clean -fd --quiet 2>/dev/null \
            && git reset --quiet --hard origin/main 2>/dev/null; then
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
        else
            warn "existing checkout looks broken, re-cloning fresh"
            cd "$HOME"
            rm -rf "$TARGET_DIR"
            git clone --quiet "$REPO_URL" "$TARGET_DIR"
            cd "$TARGET_DIR"
            final_word="installed"
            ok "re-cloned ${D}@ $(git rev-parse --short HEAD)${X}"
        fi
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

# uninstall_component <package-name>
#
# For every repo-tracked file, remove $HOME/<rel> only if it is (still) a
# symlink resolving into the repo. Anything else (a local file the user put
# there since) is left alone. If a pre-install backup exists for that path,
# the most recent one is restored in its place.
uninstall_component() {
    local pkg="$1"
    local pkg_dir="$TARGET_DIR/$pkg"

    if [ ! -d "$pkg_dir" ]; then
        warn "${B}${pkg}${X} not found, skipping"
        return
    fi

    local removed=0 restored=0 skipped=0
    while IFS= read -r src; do
        local rel="${src#$pkg_dir/}"
        local dst="$HOME/$rel"

        if [ ! -L "$dst" ]; then
            skipped=$((skipped + 1)); continue
        fi
        local resolved
        resolved="$(readlink -f "$dst" 2>/dev/null || true)"
        case "$resolved" in
            "$TARGET_DIR"/*) ;;
            *) skipped=$((skipped + 1)); continue ;;
        esac

        rm "$dst"
        removed=$((removed + 1))

        local latest_backup=""
        if [ -d "$HOME/.agent-dotfiles-backup" ]; then
            latest_backup="$(find "$HOME/.agent-dotfiles-backup" -mindepth 2 -path "*/$rel" -not -path '*/.git/*' 2>/dev/null | sort | tail -1)"
        fi
        if [ -n "$latest_backup" ]; then
            clear_broken_ancestors "$dst"
            mkdir -p "$(dirname "$dst")"
            mv "$latest_backup" "$dst"
            printf '      %s· restored %s ← %s%s\n' "$D" "$dst" "$latest_backup" "$X"
            restored=$((restored + 1))
        fi
    done < <(find "$pkg_dir" \( -type f -o -type l \) ! -path '*/.git/*')

    TOT_REMOVED=$((TOT_REMOVED + removed))
    TOT_RESTORED=$((TOT_RESTORED + restored))
    TOT_OK=$((TOT_OK + skipped))

    local detail parts=()
    [ "$removed" -gt 0 ]  && parts+=("${C}${removed} removed${X}")
    [ "$restored" -gt 0 ] && parts+=("${G}${restored} restored${X}")
    [ "$skipped" -gt 0 ]  && parts+=("${D}${skipped} skipped${X}")
    if [ ${#parts[@]} -eq 0 ]; then
        detail="${D}nothing to do${X}"
    else
        local IFS=", "; detail="${parts[*]}"
    fi
    printf '  %s✓%s %s%-12s%s %s\n' "$G" "$X" "$B" "$pkg" "$X" "$detail"
}

# ---- 3. install / uninstall -----------------------------------------------
step "Components"
TOT_REMOVED=0; TOT_RESTORED=0
for COMPONENT in $COMPONENTS; do
    case $COMPONENT in
        claude|gemini|antigravity|codex|skills)
            if [ "$MODE" = "uninstall" ]; then
                uninstall_component "$COMPONENT"
            else
                install_component "$COMPONENT"
            fi ;;
        *) warn "${B}${COMPONENT}${X} unknown, skipping" ;;
    esac
done

# ---- 4. summary ----------------------------------------------------------
if [ "$MODE" = "uninstall" ]; then
    printf '\n%s%s✓%s %sagent-dotfiles uninstalled%s\n' "$B" "$G" "$X" "$B" "$X"
    printf '  %s%s symlink(s) removed · %s restored from backup · %s left alone (not ours)%s\n' \
        "$D" "$TOT_REMOVED" "$TOT_RESTORED" "$TOT_OK" "$X"
    printf '  %srepo checkout kept at %s (delete manually if not wanted)%s\n' "$D" "$TARGET_DIR" "$X"
    printf '  %slocal-only files (history, credentials, sessions) preserved%s\n' "$D" "$X"
    printf '  %sreinstall:%s curl -fsSL .../setup.sh | bash\n\n' "$D" "$X"
else
    printf '\n%s%s✓%s %sagent-dotfiles %s%s\n' "$B" "$G" "$X" "$B" "$final_word" "$X"
    printf '  %s%s repo file(s) updated · %s linked · %s backed up · %s orphan(s) removed · %s unchanged%s\n' \
        "$D" "$repo_files_changed" "$TOT_LINKED" "$TOT_BACKED" "$TOT_ORPHAN" "$TOT_OK" "$X"
    if [ -d "$BACKUP_DIR" ]; then
        printf '  %sconflicting files moved to %s%s\n' "$D" "$BACKUP_DIR" "$X"
    fi
    printf '  %slocal-only files (history, credentials, sessions) preserved%s\n' "$D" "$X"
    printf '  %sinstall a subset:%s curl -fsSL .../setup.sh | bash -s -- claude skills\n' "$D" "$X"
    printf '  %suninstall:%s curl -fsSL .../setup.sh | bash -s -- --uninstall\n\n' "$D" "$X"
fi
