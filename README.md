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

Removes managed files that still match the repository version, restoring the most recent pre-sync backup for each path if one exists. Locally changed files, the repository checkout at `~/.agent-dotfiles`, and local-only files are left untouched:
```bash
curl -fsSL https://raw.githubusercontent.com/MauriceDHanisch/agent-dotfiles/main/setup.sh | bash -s -- --uninstall
```

To reinstall from scratch, uninstall then install again:
```bash
curl -fsSL https://raw.githubusercontent.com/MauriceDHanisch/agent-dotfiles/main/setup.sh | bash -s -- --uninstall
curl -fsSL https://raw.githubusercontent.com/MauriceDHanisch/agent-dotfiles/main/setup.sh | bash
```

## Structure

This repository uses a "dotfiles" approach where multiple tool configurations are stored in one place and explicitly copied into your home directory when you run the installer.

Local-only files (history, credentials, sessions, sqlite dbs) are left untouched. When a managed file differs from its tracked version, it is moved to `~/.agent-dotfiles-backup/<timestamp>/` before the repository version replaces it.

- `guidelines.md`: The **Source of Truth** for global agent instructions. Claude / Gemini / Codex / Antigravity receive copies as `CLAUDE.md`, `GEMINI.md`, and `AGENTS.md` on sync. Cursor gets the same text as an always-apply rule at `~/.cursor/rules/guidelines.mdc` (regenerated from `guidelines.md` on install, because Cursor rules need YAML frontmatter).
- `claude/`: Claude Code configurations (`~/.claude`).
- `gemini/`: Gemini CLI configurations (`~/.gemini`).
- `codex/`: Codex configurations (`~/.codex`).
- `codex-bin`: Custom Codex binary. It downloads the matching checksum-verified release asset from `MauriceDHanisch/codex` into `~/.local/opt/codex/<version>/`, links `codex` plus its helper binaries into `~/.local/bin/`, and links that release's `bin/` directory into `$CODEX_HOME/packages/standalone/current/` so `codex agents` can start the custom app-server. The installer selects Apple Silicon macOS or x86_64 Linux automatically. Existing official managed installs are preserved. Deselect it to retain an existing official Codex installation. Set `CODEX_RELEASE_TAG` to install a specific release instead of the latest one.
- `cursor/`: Cursor configurations (`~/.cursor`): always-apply guidelines rule, `statusline.sh`, `cli-preferences.json`, and `permissions.json`. The live `~/.cursor/cli-config.json` stays local (auth/cache). On install, portable keys from `cli-preferences.json` are deep-merged into it (prefs win on conflict; machine-only keys are kept). `permissions.json` steers Auto-review via `autoRun.block_instructions` / `allow_instructions` (Cursor CLI has no Claude-style `ask` list; `deny` hard-blocks instead of prompting).
- `skills/`: Shared agent skills (`~/.agents/skills`). Cursor also discovers skills from `~/.claude/skills/` and `~/.codex/skills/`, so no Cursor-local skill copies are needed.

## How to Manage

1. **Edit Guidelines**: Modify `guidelines.md` at the root, commit and push it, then re-run the installer. This copies the update into every agent's live configuration, including Cursor's regenerated `guidelines.mdc`.
2. **Edit Cursor CLI prefs**: Change `cursor/.cursor/cli-preferences.json`, then re-run `bash setup.sh cursor` to deep-merge into `~/.cursor/cli-config.json`.
3. **Edit Auto-review ask/block policy**: Change `cursor/.cursor/permissions.json` (`autoRun`), then re-run the installer to copy it to `~/.cursor/permissions.json`.
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
- `bash`, `cmp`, `find`, `readlink` (standard on macOS and Linux)
- `jq` (for Cursor statusline + deep-merging `cli-preferences.json`)
- `bc` (for Cursor statusline token formatting)

## Custom Codex Releases

The custom Codex fork is released from its `maurice` branch through the
`maurice-release` GitHub Actions workflow. Run it manually with a tag such as
`v0.147.0-maurice.1`; it builds Apple Silicon macOS plus static x86_64 and
ARM64 Linux bundles, then publishes the bundles and `SHA256SUMS` as a GitHub
Release.

The normal installer selects the matching asset automatically when `codex-bin`
is selected. It also links that release's `bin/` directory into
`$CODEX_HOME/packages/standalone/current/` (defaulting to `~/.codex`) for
shared app-server commands such as `codex agents`. To install configuration
without replacing an existing Codex binary, select only `codex`. To pin a host
to a specific version, set `CODEX_RELEASE_TAG` as shown below. The custom
managed link is intended for `codex agents`
and daemon `start`; do not use daemon `bootstrap` with it until the custom fork
disables the official updater:

```bash
CODEX_RELEASE_TAG=v0.147.0-maurice.1 bash setup.sh codex-bin
```

## Credits

- The `tdd-workflow` skill is adapted from [ryanliu30/claude-setup](https://github.com/ryanliu30/claude-setup), which in turn credits [affaan-m/everything-claude-code](https://github.com/affaan-m/everything-claude-code).
