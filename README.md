# Agent Dotfiles

A unified, industry-standard configuration for Claude, Gemini, and Codex agents. Pure-bash installer, no system dependencies beyond `git`.

## Install / Update

**Install everything:**
```bash
curl -fsSL https://raw.githubusercontent.com/MauriceDHanisch/agent-dotfiles/main/setup.sh | bash
```

**Install specific agents only:**
```bash
# Example: Only Claude and Shared Skills
curl -fsSL https://raw.githubusercontent.com/MauriceDHanisch/agent-dotfiles/main/setup.sh | bash -s -- claude skills
```

Valid components: `claude`, `gemini`, `codex`, `skills`.

## Uninstall

Removes the symlinks this installer created, restoring the most recent pre-install backup for each path if one exists. The repo checkout at `~/.agent-dotfiles` and any local-only files are left untouched:
```bash
curl -fsSL https://raw.githubusercontent.com/MauriceDHanisch/agent-dotfiles/main/setup.sh | bash -s -- --uninstall
```

To reinstall from scratch, uninstall then install again:
```bash
curl -fsSL https://raw.githubusercontent.com/MauriceDHanisch/agent-dotfiles/main/setup.sh | bash -s -- --uninstall
curl -fsSL https://raw.githubusercontent.com/MauriceDHanisch/agent-dotfiles/main/setup.sh | bash
```

## Structure

This repository uses a "dotfiles" approach where multiple tool configurations are stored in one place and symlinked to your home directory.

Local-only files (history, credentials, sessions, sqlite dbs) are left untouched. When a local file conflicts with a tracked file, it is moved to `~/.agent-dotfiles-backup/<timestamp>/` before the symlink is created.

- `guidelines.md`: The **Source of Truth** for global agent instructions. All agents (`CLAUDE.md`, `GEMINI.md`, `AGENTS.md`) are symlinked to this file.
- `claude/`: Claude Code configurations (`~/.claude`).
- `gemini/`: Gemini CLI configurations (`~/.gemini`).
- `codex/`: Codex configurations (`~/.codex`).
- `skills/`: Shared agent skills (`~/.agents/skills`).

## How to Manage

1. **Edit Guidelines**: Modify `guidelines.md` at the root. The changes will automatically propagate to all agents because they are symlinked.
2. **Add Skills**: Add new `.md` files to `skills/.agents/skills/`.
3. **Sync**:
   ```bash
   cd ~/.agent-dotfiles
   git add .
   git commit -m "update guidelines"
   git push
   ```

## Requirements
- `git`
- `bash`, `find`, `ln`, `readlink` (standard on macOS and Linux)

## Credits

- The `tdd-workflow` skill is adapted from [ryanliu30/claude-setup](https://github.com/ryanliu30/claude-setup), which in turn credits [affaan-m/everything-claude-code](https://github.com/affaan-m/everything-claude-code).
