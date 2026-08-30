#!/usr/bin/env bash
# Agent Dotfiles installer.
#
#   curl -fsSL https://raw.githubusercontent.com/MauriceDHanisch/agent-dotfiles/main/setup.sh | bash
#
# Clones/updates ~/.agent-dotfiles and copies each agent's config into $HOME.
# With no arguments on an interactive terminal it shows a key-driven picker for
# which components to install (default: all selected). Pass names to skip it:
#
#   curl -fsSL .../setup.sh | bash -s -- claude skills
#
# Pass --uninstall to remove managed files that still match the repository
# version, restoring the most recent pre-install backup for each path when one
# exists. The repo checkout at
# ~/.agent-dotfiles and any local-only files are left untouched:
#
#   curl -fsSL .../setup.sh | bash -s -- --uninstall
#   curl -fsSL .../setup.sh | bash -s -- --uninstall claude skills
set -eo pipefail

REPO_URL="${AGENT_DOTFILES_REPO:-https://github.com/MauriceDHanisch/agent-dotfiles.git}"
TARGET_DIR="$HOME/.agent-dotfiles"
BACKUP_DIR="$HOME/.agent-dotfiles-backup/$(date +%Y%m%d-%H%M%S)"
ALL_COMPONENTS="claude gemini antigravity codex codex-bin cursor skills"

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
        codex-bin)   echo "Custom Codex    ~/.local/bin/codex" ;;
        cursor)      echo "Cursor          ~/.cursor" ;;
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

CODEX_RELEASE_REPO="${CODEX_RELEASE_REPO:-MauriceDHanisch/codex}"
CODEX_RELEASE_TAG="${CODEX_RELEASE_TAG:-latest}"

codex_target() {
    case "$(uname -s)/$(uname -m)" in
        Darwin/arm64) printf '%s' 'aarch64-apple-darwin' ;;
        Linux/x86_64) printf '%s' 'x86_64-unknown-linux-musl' ;;
        Linux/aarch64|Linux/arm64) printf '%s' 'aarch64-unknown-linux-musl' ;;
        *) return 1 ;;
    esac
}

sha256_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        return 1
    fi
}

link_codex_binary() {
    local source="$1" binary destination backup_path
    binary="$(basename "$source")"
    destination="$HOME/.local/bin/$binary"
    if [ -e "$destination" ] && [ ! -L "$destination" ]; then
        backup_path="$BACKUP_DIR/.local/bin/$binary"
        mkdir -p "$(dirname "$backup_path")"
        mv "$destination" "$backup_path"
        warn "backed up existing ${D}$destination${X}"
    fi
    mkdir -p "$(dirname "$destination")"
    ln -sfn "$source" "$destination"
}

link_codex_managed_install() {
    local codex_home="$1" install_dir="$2"
    local managed_root managed_current managed_marker marker_tmp managed_bin
    managed_root="$codex_home/packages/standalone"
    managed_current="$managed_root/current"
    managed_marker="$managed_root/.agent-dotfiles-custom"
    managed_bin="$install_dir/bin"

    if { [ -e "$managed_current" ] || [ -L "$managed_current" ]; } \
        && [ ! -f "$managed_marker" ]; then
        warn "existing managed Codex install preserved at ${D}$managed_current${X}"
        warn "remove it before rerunning if you want the custom managed path"
        return 0
    fi
    if [ -e "$managed_current" ] && [ ! -L "$managed_current" ]; then
        warn "managed Codex path is not a symlink; preserved at ${D}$managed_current${X}"
        return 0
    fi

    mkdir -p "$managed_root"
    ln -sfn "$managed_bin" "$managed_current"
    if [ ! -x "$managed_current/codex" ]; then
        warn "managed Codex link was not created at ${D}$managed_current${X}"
        return 0
    fi

    marker_tmp="$managed_marker.$$"
    printf '%s\n' "$managed_bin" >"$marker_tmp"
    mv -f "$marker_tmp" "$managed_marker"
    ok "managed Codex path linked for ${D}codex agents${X}"
}

install_codex_binary() {
    local target tag release_json asset archive_url checksum_url tmp_dir expected actual install_dir binary codex_home
    target="$(codex_target)" || {
        warn "Codex binary unavailable for $(uname -s)/$(uname -m)"
        return
    }
    if ! command -v curl >/dev/null 2>&1; then
        warn "curl not found; skipped custom Codex binary install"
        return
    fi
    if [ "$CODEX_RELEASE_TAG" = "latest" ]; then
        release_json="$(curl -fsSL "https://api.github.com/repos/${CODEX_RELEASE_REPO}/releases/latest")" || {
            warn "no custom Codex release published yet; skipped binary install"
            return
        }
        tag="$(printf '%s\n' "$release_json" | sed -nE 's/^[[:space:]]*"tag_name":[[:space:]]*"([^"]+)".*/\1/p' | head -n 1)"
        if [ -z "$tag" ]; then
            warn "could not read the latest custom Codex release tag; skipped binary install"
            return
        fi
    else
        tag="$CODEX_RELEASE_TAG"
    fi
    case "$tag" in
        ''|*[!A-Za-z0-9._-]*)
            warn "invalid custom Codex release tag: ${tag}"
            return
            ;;
    esac
    asset="codex-${target}.tar.gz"
    install_dir="$HOME/.local/opt/codex/$tag"
    if [ ! -x "$install_dir/bin/codex" ]; then
        tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/codex-install.XXXXXX")"
        archive_url="https://github.com/${CODEX_RELEASE_REPO}/releases/download/${tag}/${asset}"
        checksum_url="https://github.com/${CODEX_RELEASE_REPO}/releases/download/${tag}/SHA256SUMS"
        if ! curl -fsSL "$archive_url" -o "$tmp_dir/$asset" \
            || ! curl -fsSL "$checksum_url" -o "$tmp_dir/SHA256SUMS"; then
            rm -rf "$tmp_dir"
            warn "failed to download custom Codex ${tag}"
            return
        fi
        expected="$(awk -v asset="$asset" '$2 == asset { print $1 }' "$tmp_dir/SHA256SUMS")"
        actual="$(sha256_file "$tmp_dir/$asset")" || {
            rm -rf "$tmp_dir"
            warn "sha256sum or shasum is required for custom Codex"
            return
        }
        if [ -z "$expected" ] || [ "$expected" != "$actual" ]; then
            rm -rf "$tmp_dir"
            warn "checksum verification failed for custom Codex ${tag}"
            return
        fi
        tar -xzf "$tmp_dir/$asset" -C "$tmp_dir"
        if [ ! -x "$tmp_dir/codex-${target}/bin/codex" ]; then
            rm -rf "$tmp_dir"
            warn "custom Codex archive has an unexpected layout"
            return
        fi
        mkdir -p "$(dirname "$install_dir")"
        if [ -e "$install_dir" ] || [ -L "$install_dir" ]; then
            rm -rf "$install_dir"
        fi
        mv "$tmp_dir/codex-${target}" "$install_dir"
        rm -rf "$tmp_dir"
    fi
    for binary in codex codex-code-mode-host codex-responses-api-proxy; do
        if [ -x "$install_dir/bin/$binary" ]; then
            link_codex_binary "$install_dir/bin/$binary"
        fi
    done
    codex_home="${CODEX_HOME:-$HOME/.codex}"
    link_codex_managed_install "$codex_home" "$install_dir"
    ok "custom Codex ${D}${tag}${X} installed for ${D}${target}${X}"
}

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

TOT_COPIED=0; TOT_BACKED=0; TOT_OK=0

# install_component <package-name>
#
# The repository is the source of truth. Changed managed files are backed up,
# then replaced with regular copies. Local-only files are never touched.
install_component() {
    local pkg="$1"
    local pkg_dir="$TARGET_DIR/$pkg"

    if [ ! -d "$pkg_dir" ]; then
        warn "${B}${pkg}${X} not found, skipping"
        return
    fi

    local copied=0 backed_up=0 skipped=0
    while IFS= read -r src; do
        local rel="${src#$pkg_dir/}"
        local dst="$HOME/$rel"

        # A matching regular file is already in sync. Symlinks are intentionally
        # replaced so live configuration never edits the repository indirectly.
        if [ -f "$dst" ] && [ ! -L "$dst" ] && cmp -s "$src" "$dst"; then
            skipped=$((skipped + 1))
            continue
        fi

        # Preserve any previous managed or local version before replacing it.
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
        cp -p "$src" "$dst"
        copied=$((copied + 1))
    done < <(find "$pkg_dir" \( -type f -o -type l \) ! -path '*/.git/*')

    TOT_COPIED=$((TOT_COPIED + copied))
    TOT_BACKED=$((TOT_BACKED + backed_up))
    TOT_OK=$((TOT_OK + skipped))

    # Mention only what actually happened.
    local detail parts=()
    [ "$copied" -gt 0 ]    && parts+=("${G}${copied} copied${X}")
    [ "$backed_up" -gt 0 ] && parts+=("${C}${backed_up} backed up${X}")
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
# For every repo-tracked file, remove $HOME/<rel> only if it still matches the
# repository copy. Anything changed locally is left alone. If a pre-sync
# backup exists for that path, the most recent one is restored in its place.
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

        if [ ! -f "$dst" ] || [ -L "$dst" ] || ! cmp -s "$src" "$dst"; then
            skipped=$((skipped + 1)); continue
        fi

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

# Rebuild Cursor's always-apply rule from guidelines.md so Cursor keeps the
# same source of truth as CLAUDE.md / AGENTS.md / GEMINI.md. Cursor rules need
# YAML frontmatter, so this generated copy is necessary.
sync_cursor_guidelines() {
    local out="$TARGET_DIR/cursor/.cursor/rules/guidelines.mdc"
    mkdir -p "$(dirname "$out")"
    {
        printf '%s\n' '---' \
            'description: Global agent guidelines (synced from guidelines.md)' \
            'alwaysApply: true' \
            '---' \
            ''
        cat "$TARGET_DIR/guidelines.md"
    } > "$out"
}

# cli-config.json is local/machine state (auth caches, model picker). Deep-merge
# portable prefs from cli-preferences.json so installs do not clobber the rest.
# Prefs win on conflict; keys only in cli-config.json (authInfo, caches, …) are kept.
ensure_cursor_cli_config() {
    local cfg="$HOME/.cursor/cli-config.json"
    local prefs="$TARGET_DIR/cursor/.cursor/cli-preferences.json"
    if [ ! -f "$prefs" ]; then
        warn "missing ${D}$prefs${X}; skip cli-config merge"
        return
    fi
    if [ ! -f "$cfg" ]; then
        warn "no $cfg yet; create one (or start Cursor CLI once), then re-run: bash setup.sh cursor"
        return
    fi
    if ! command -v jq >/dev/null 2>&1; then
        warn "jq not found; skip merging Cursor cli-preferences.json"
        return
    fi
    local tmp
    tmp="$(mktemp)"
    if jq -s '
        def deepmerge($a; $b):
          if ($a | type) == "object" and ($b | type) == "object" then
            reduce (($a + $b) | keys_unsorted[]) as $k
              ({}; .[$k] = deepmerge($a[$k]; $b[$k]))
          elif $b == null then
            $a
          else
            $b
          end;
        deepmerge(.[0]; .[1])
      ' "$cfg" "$prefs" >"$tmp"; then
        mv "$tmp" "$cfg"
        ok "merged ${D}cli-preferences.json${X} → ${D}~/.cursor/cli-config.json${X}"
    else
        rm -f "$tmp"
        warn "failed to merge Cursor cli-preferences.json"
    fi
}

# ---- 3. install / uninstall -----------------------------------------------
step "Components"
TOT_REMOVED=0; TOT_RESTORED=0
for COMPONENT in $COMPONENTS; do
    case $COMPONENT in
        claude|gemini|antigravity|codex|cursor|skills)
            if [ "$MODE" = "uninstall" ]; then
                uninstall_component "$COMPONENT"
            else
                if [ "$COMPONENT" = "cursor" ]; then
                    sync_cursor_guidelines
                fi
                install_component "$COMPONENT"
                if [ "$COMPONENT" = "cursor" ]; then
                    ensure_cursor_cli_config
                fi
            fi ;;
        codex-bin)
            if [ "$MODE" = "uninstall" ]; then
                warn "custom Codex binaries are retained in ~/.local/opt/codex"
            else
                install_codex_binary
            fi ;;
        *) warn "${B}${COMPONENT}${X} unknown, skipping" ;;
    esac
done

# ---- 4. summary ----------------------------------------------------------
if [ "$MODE" = "uninstall" ]; then
    printf '\n%s%s✓%s %sagent-dotfiles uninstalled%s\n' "$B" "$G" "$X" "$B" "$X"
    printf '  %s managed file(s) removed · %s restored from backup · %s left alone (changed locally)%s\n' \
        "$D" "$TOT_REMOVED" "$TOT_RESTORED" "$TOT_OK" "$X"
    printf '  %srepo checkout kept at %s (delete manually if not wanted)%s\n' "$D" "$TARGET_DIR" "$X"
    printf '  %slocal-only files (history, credentials, sessions) preserved%s\n' "$D" "$X"
    printf '  %sreinstall:%s curl -fsSL .../setup.sh | bash\n\n' "$D" "$X"
else
    printf '\n%s%s✓%s %sagent-dotfiles %s%s\n' "$B" "$G" "$X" "$B" "$final_word" "$X"
    printf '  %s%s repo file(s) updated · %s copied · %s backed up · %s unchanged%s\n' \
        "$D" "$repo_files_changed" "$TOT_COPIED" "$TOT_BACKED" "$TOT_OK" "$X"
    if [ -d "$BACKUP_DIR" ]; then
        printf '  %sconflicting files moved to %s%s\n' "$D" "$BACKUP_DIR" "$X"
    fi
    printf '  %slocal-only files (history, credentials, sessions) preserved%s\n' "$D" "$X"
    printf '  %sinstall a subset:%s curl -fsSL .../setup.sh | bash -s -- claude skills\n' "$D" "$X"
    printf '  %suninstall:%s curl -fsSL .../setup.sh | bash -s -- --uninstall\n\n' "$D" "$X"
fi
