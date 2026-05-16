#!/bin/bash
set -e

REPO_URL="https://github.com/MauriceDHanisch/agent-dotfiles.git"
TARGET_DIR="$HOME/.agent-dotfiles"
BACKUP_DIR="$HOME/.agent-dotfiles-backup/$(date +%Y%m%d-%H%M%S)"

echo "AI Agent Dotfiles setup starting..."
echo ""

# 1. Clone/Update Repo. The repo is a mirror of upstream; plain `git pull`
# breaks on force-pushes, so hard-reset to origin/main.
if [ ! -d "$TARGET_DIR" ]; then
    echo "→ Cloning agent-dotfiles to $TARGET_DIR..."
    git clone "$REPO_URL" "$TARGET_DIR"
else
    echo "→ Updating agent-dotfiles in $TARGET_DIR..."
    cd "$TARGET_DIR" && git fetch --quiet origin && git reset --quiet --hard origin/main
fi

# 2. Determine what to install
cd "$TARGET_DIR"
COMPONENTS=("$@")

if [ ${#COMPONENTS[@]} -eq 0 ]; then
    echo "→ No specific agents requested. Installing all components..."
    COMPONENTS=("claude" "gemini" "codex" "skills")
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

# install_component <package-name>
#
# The repo is the source of truth. For every file tracked in the package
# we ensure $HOME/<rel> is a symlink to the repo file.
# After linking, removes any orphan symlinks under the package's target
# tree that point into the repo but whose target no longer exists.
# Files that exist only locally (history, credentials, sessions, sqlite
# dbs, ...) are never touched.
install_component() {
    local pkg="$1"
    local pkg_dir="$TARGET_DIR/$pkg"

    if [ ! -d "$pkg_dir" ]; then
        echo "⚠️  Package $pkg not found at $pkg_dir, skipping"
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
            echo "  backup: $dst -> $backup_path"
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
                echo "  orphan: removed $link"
                orphans=$((orphans + 1))
            fi
        done < <(find "$target_root" -type l 2>/dev/null)
    fi

    echo "→ $pkg: $linked linked, $backed_up backed up, $orphans orphan(s) removed, $skipped already correct"
}

# 3. Install
echo "→ Linking selected components: ${COMPONENTS[*]}"

for COMPONENT in "${COMPONENTS[@]}"; do
    case $COMPONENT in
        claude|gemini|codex|skills) install_component "$COMPONENT" ;;
        *) echo "⚠️  Unknown component: $COMPONENT (skipping)" ;;
    esac
done

echo ""
echo "✅ AI Agent Dotfiles setup complete!"
echo ""
echo "NOTE: Local-only files (history, credentials, sessions) were preserved."
if [ -d "$BACKUP_DIR" ]; then
    echo "      Files that conflicted with the repo were moved to:"
    echo "        $BACKUP_DIR"
fi
echo ""
echo "To install specific agents only:"
echo "  curl -fsSL https://raw.githubusercontent.com/MauriceDHanisch/agent-dotfiles/main/setup.sh | bash -s -- claude skills"
