# Global Agent Guidelines

These guidelines apply to all workspaces and interactions.

## 1. Python environment

Use `uv run <cmd>` (e.g. `uv run python ...`, `uv run pytest`). This needs no activation and avoids permission prompts. If `uv` is unavailable, fall back to `source .venv/bin/activate` (adjust path as needed). Use conda only when no `.venv`, `venv`, or `env` directory exists.

## 2. Modes: prototype (default) vs solid (opt in)

Default is prototype mode. Optimize for speed and readability. Prefer flat scripts over abstractions. Cover the happy path only. Add no tests, no error handling, and no future proofing unless asked.

Solid mode applies only when the user explicitly asks with words such as "reusable", "solid", "production", or "thesis pipeline". Write like a senior engineer minimizing lines of code: small functions, no duplication, no dead code, minimal API surface. Add tests only when asked. Add nothing speculative.

## 3. Minimal code, no comments, no overengineering

Write minimal code with minimal prose. No comments unless the logic is non obvious and cannot be made obvious by renaming. Never narrate syntax, never add step tracking comments, never add docstrings to trivial functions, never summarize changes in code. If renaming removes the need for a comment, rename instead of commenting.

Do not overengineer. No classes when a function works. No helpers used once. No config, factory, or wrapper layers for a single use case. No verbose output: answer briefly and skip fluff.

## 4. Math formatting in chat

When replying in chat (not editing a `.tex` file or Markdown that renders), never use LaTeX delimiters (`$...$`, `$$...$$`, `\frac`, `\sqrt`, etc.). LaTeX source is hard to read unrendered.

Use readable plain text math with Unicode symbols and clear spacing. Superscripts and subscripts: `x²`, `aₙ`, `H₂O` (or `x^2`, `a_n` when Unicode is awkward). Common symbols: `√`, `∑`, `∫`, `∂`, `∇`, `≈`, `≤`, `≥`, `≠`, `→`, `±`, `×`, `·`, `∞`, Greek letters (`α`, `β`, `θ`, `λ`, `μ`, `σ`, `π`). Write fractions inline as `a / b`. For multi line derivations, use plain text rows with the `=` signs lined up. Lay out vectors and matrices with spacing or simple bracket rows, not `\begin{matrix}`.

Use LaTeX only when the target file actually renders it. If unsure whether the destination renders, default to plain text math.

## 5. Punctuation

Banned characters in all output (chat, code, code comments, commits, docs): — and –. Banned punctuation use of double hyphens, including spaced form (word, double hyphen, word) and any range or separator use. The only allowed double hyphen is a real CLI flag (e.g. `git commit --amend`). Never use any of these as a pause or separator. Rewrite the sentence with a comma, a colon, or two sentences instead.

## 6. Testing

Write tests only when asked, in either mode. When you do:

- Use end to end tests as the only testing mechanism. Prove a complex feature works by running the real entry point on real or realistic input.
- Every E2E run ends with a verifiable, repeatable artifact: an output file, metrics JSON, log, plot, or screenshot, produced by one rerunnable command with fixed seeds and inputs.
- Never write unit tests after the code exists. They only confirm what the code already does.
- If a component must be tested in isolation, first list every way it can fail, then write tests for those failure modes, then write the code.
