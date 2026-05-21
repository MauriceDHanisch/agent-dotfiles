---
model: haiku
---

Run `make check` in the repo, fix everything that can be fixed without changing logic, and report what remains.

## Steps

1. Run `make check` and capture the full output.
2. For each failure category, apply fixes where safe:
   - **Formatting**: auto-fix (e.g. `black`, `ruff format`, `isort`) — always safe.
   - **Linting**: fix rule violations that don't require logic changes (unused imports, missing whitespace, style issues). Skip anything that would alter behavior.
   - **Type errors**: fix annotation issues properly. Rules:
     - In `src/`: **never** use `# type: ignore` — fix the types correctly or report as requiring manual attention.
     - In test files: `# type: ignore` is acceptable only when it meaningfully reduces boilerplate and a proper fix would require many extra lines.
     - Do **not** change runtime logic to satisfy the type checker.
   - **Tests**: investigate failures. Fix broken tests only if the test itself is wrong (e.g. stale expected value, wrong import). Do **not** change production logic to make tests pass — report those failures.
3. Re-run `make check` to confirm all auto-fixable issues are resolved.
4. Produce a final summary with two sections:
   - **Fixed**: bullet list of what was resolved and how.
   - **Requires manual attention**: bullet list of remaining issues with a one-line explanation of why each needs a logic change.
