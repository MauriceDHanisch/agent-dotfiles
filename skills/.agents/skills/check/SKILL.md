---
name: "check"
description: "Run make check, safely fix formatting/lint/type issues that do not change runtime logic, and report remaining failures. Use when the user asks to run checks, make check, lint, format, typecheck, or clean up safe check failures."
---

# Check

Run `make check` in the repo, fix everything that can be fixed without changing logic, and report what remains.

## Steps

1. Run `make check` and capture the full output.
2. For each failure category, apply fixes where safe:
   - **Formatting**: auto-fix, for example `black`, `ruff format`, or `isort`, when configured by the project.
   - **Linting**: fix rule violations that do not require logic changes, such as unused imports, missing whitespace, and style issues. Skip anything that would alter behavior.
   - **Type errors**: fix annotation issues properly.
     - In `src/`: never use `# type: ignore`; fix the types correctly or report as requiring manual attention.
     - In test files: `# type: ignore` is acceptable only when it meaningfully reduces boilerplate and a proper fix would require many extra lines.
     - Do not change runtime logic to satisfy the type checker.
   - **Tests**: investigate failures. Fix broken tests only if the test itself is wrong, for example stale expected values or wrong imports. Do not change production logic to make tests pass; report those failures.
3. Re-run `make check` to confirm all auto-fixable issues are resolved.
4. Produce a final summary with two sections:
   - **Fixed**: bullet list of what was resolved and how.
   - **Requires manual attention**: bullet list of remaining issues with a one-line explanation of why each needs a logic change.
