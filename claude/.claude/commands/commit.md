---
model: haiku
---

Analyze the currently staged git files and create a high-quality commit for them.

## Steps

1. Run `git diff --cached --stat`. If nothing is staged, tell the user and stop.
2. Run `git log --oneline -20` to infer the repo's commit style convention: casing, prefix format (`feat:`, `feat(scope):`, `[feat]`, none, etc.), verb tense, and typical subject length.
3. Run `git diff --cached` to read the full diff.
4. Analyze the diff deeply: understand *what* changed and *why* — infer intent from the code, not just filenames.
5. Perform a high-level bug check: scan for obvious issues such as syntax errors, type mismatches, broken imports, logic errors, unhandled exceptions, and test failures. Flag any concerns found.
6. Write a commit message that:
   - Follows the style convention already used in this repo.
   - Has a concise subject line (≤72 chars) in imperative mood that states *what* the commit does.
   - Includes a body when the *why* or *how* is non-obvious: wrap at 72 chars, separated from subject by a blank line, focused on motivation and context rather than restating the diff.
   - Is specific and precise — avoid vague words like "update", "fix things", "improve", "refactor stuff".
7. Run `git commit` using a heredoc to preserve formatting.
8. Confirm with `git status`.

## Absolute rules
- **Never** add `Co-Authored-By` or any mention of Claude.
- Do **not** stage additional files — only commit what is already staged.
- **Do not commit if bugs are detected.** If the bug check (step 5) identifies any issues, report them to the user and refuse to create the commit until they are resolved.
