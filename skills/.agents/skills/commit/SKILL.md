---
name: "commit"
description: "Analyze currently staged git changes and create a high-quality commit message and commit. Use when the user asks to commit staged changes."
---

# Commit

Analyze the currently staged git files and create a high-quality commit for them.

## Steps

1. Run `git diff --cached --stat`. If nothing is staged, tell the user and stop.
2. Run `git log --oneline -20` to infer the repo's commit style convention: casing, prefix format (`feat:`, `feat(scope):`, `[feat]`, none, etc.), verb tense, and typical subject length.
3. Run `git diff --cached` to read the full diff.
4. Analyze the diff deeply: understand what changed and why. Infer intent from the code, not just filenames.
5. Perform a high-level bug check: scan for obvious issues such as syntax errors, type mismatches, broken imports, logic errors, unhandled exceptions, and test failures. Flag any concerns found.
6. Write a commit message that:
   - Follows the style convention already used in this repo.
   - Has a concise subject line, 72 characters or fewer, in imperative mood that states what the commit does.
   - Includes a body when the why or how is non-obvious: wrap at 72 characters, separated from subject by a blank line, focused on motivation and context rather than restating the diff.
   - Is specific and precise. Avoid vague words like "update", "fix things", "improve", or "refactor stuff".
7. Run `git commit` using a heredoc to preserve formatting.
8. Confirm with `git status`.

## Absolute Rules

- Never add `Co-Authored-By` or any mention of AI assistants.
- Do not stage additional files. Only commit what is already staged.
- Do not commit if bugs are detected. If the bug check identifies issues, report them to the user and refuse to create the commit until they are resolved.
