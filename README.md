# Agent Dotfiles

A unified, industry-standard configuration for Claude, Gemini, Codex, and Cursor agents. Pure-bash installer, no system dependencies beyond `git`.

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

Valid components: `claude`, `gemini`, `antigravity`, `codex`, `cursor`, `skills`.

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

- `guidelines.md`: The **Source of Truth** for global agent instructions. Claude / Gemini / Codex / Antigravity point at this file via symlinks (`CLAUDE.md`, `GEMINI.md`, `AGENTS.md`). Cursor gets the same text as an always-apply rule at `~/.cursor/rules/guidelines.mdc` (regenerated from `guidelines.md` on install, because Cursor rules need YAML frontmatter).
- `claude/`: Claude Code configurations (`~/.claude`).
- `gemini/`: Gemini CLI configurations (`~/.gemini`).
- `codex/`: Codex configurations (`~/.codex`).
- `cursor/`: Cursor configurations (`~/.cursor`): always-apply guidelines rule, `statusline.sh`, `cli-preferences.json`, and `permissions.json`. The live `~/.cursor/cli-config.json` stays local (auth/cache). On install, portable keys from `cli-preferences.json` are deep-merged into it (prefs win on conflict; machine-only keys are kept). `permissions.json` steers Auto-review via `autoRun.block_instructions` / `allow_instructions` (Cursor CLI has no Claude-style `ask` list; `deny` hard-blocks instead of prompting).
- `skills/`: Shared agent skills (`~/.agents/skills`). Cursor also discovers skills from `~/.claude/skills/` and `~/.codex/skills/`, so no Cursor-local skill copies are needed.

## How to Manage

1. **Edit Guidelines**: Modify `guidelines.md` at the root. Re-run the installer (or `bash setup.sh cursor`) so Cursor's `guidelines.mdc` is regenerated. Other agents pick up changes immediately via symlink.
2. **Edit Cursor CLI prefs**: Change `cursor/.cursor/cli-preferences.json`, then re-run `bash setup.sh cursor` to deep-merge into `~/.cursor/cli-config.json`.
3. **Edit Auto-review ask/block policy**: Change `cursor/.cursor/permissions.json` (`autoRun`). It is symlinked to `~/.cursor/permissions.json` on install.
4. **Add Skills**: Add new skill folders under `skills/.agents/skills/`.
5. **Sync**:
   ```bash
   cd ~/.agent-dotfiles
   git add .
   git commit -m "update guidelines"
   git push
   ```

## Requirements
- `git`
- `bash`, `find`, `ln`, `readlink` (standard on macOS and Linux)
- `jq` (for Cursor statusline + deep-merging `cli-preferences.json`)
- `bc` (for Cursor statusline token formatting)

## Credits

- The `tdd-workflow` skill is adapted from [ryanliu30/claude-setup](https://github.com/ryanliu30/claude-setup), which in turn credits [affaan-m/everything-claude-code](https://github.com/affaan-m/everything-claude-code).
