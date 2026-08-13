# Agent Dotfiles

A unified, industry-standard configuration for Claude, Gemini, Codex, and Cursor agents. Bash installer with standard command-line tools.

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

Valid components: `claude`, `gemini`, `antigravity`, `codex`, `codex-bin`, `cursor`, `skills`.

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
- `codex-bin`: Custom Codex binary. It downloads the matching checksum-verified release asset from `MauriceDHanisch/codex` into `~/.local/opt/codex/<version>/` and links `codex` plus its helper binaries into `~/.local/bin/`. The installer selects Apple Silicon macOS or x86_64 Linux automatically. Deselect it to retain an existing official Codex installation. Set `CODEX_RELEASE_TAG` to install a specific release instead of the latest one.
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
- `curl`, `tar`, and either `sha256sum` or `shasum` (for custom Codex binary installation)
- `bash`, `find`, `ln`, `readlink` (standard on macOS and Linux)
- `jq` (for Cursor statusline + deep-merging `cli-preferences.json`)
- `bc` (for Cursor statusline token formatting)

## Custom Codex Releases

The custom Codex fork is released from its `maurice` branch through the
`maurice-release` GitHub Actions workflow. Run it manually with a tag such as
`v0.147.0-maurice.1`; it builds Apple Silicon macOS plus static x86_64 and
ARM64 Linux bundles, then publishes the bundles and `SHA256SUMS` as a GitHub
Release.

The normal installer selects the matching asset automatically when `codex-bin`
is selected. To install configuration without replacing an existing Codex
binary, select only `codex`. To pin a host to a specific version:

```bash
CODEX_RELEASE_TAG=v0.147.0-maurice.1 bash setup.sh codex-bin
```

## Credits

- The `tdd-workflow` skill is adapted from [ryanliu30/claude-setup](https://github.com/ryanliu30/claude-setup), which in turn credits [affaan-m/everything-claude-code](https://github.com/affaan-m/everything-claude-code).
