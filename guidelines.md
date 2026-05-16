# Global Agent Guidelines

These guidelines apply to **all workspaces** and interactions.

## I. Environment & Terminal Operations (Universal Priority)

**CRITICAL**: Before running any Python scripts, tests, or installing packages via the terminal, you **MUST** ensure the correct environment is active.

### 1. Execution Strategy
1. **Check for Local Venv (Priority)**:
   - Look for a directory named `.venv`, `venv`, or `env` in the project root. The user normally uses uv.
   - *Action*: If found, activate using `source .venv/bin/activate` or use `uv run` (adjust path as needed).
2. **Check for Conda (Fallback)**:
   - If no local venv exists, infer the Conda environment name (often matches project folder name, course number like `144`, or project title).
   - *Action*: Run `conda activate <inferred_name>`. If unsure, run `conda env list`.

### 2. Environment Verification
- **Prompt Check**: Always check the current terminal prompt (e.g., `(base)` vs `(densityNO)`) before executing. If the prompt implies the wrong environment, activate the correct one immediately.
- **Path Check**: If uncertain, run `which python` to verify the active interpreter path.

### 3. Code Verification
- **Hooks & Tests**: Always run `./.git/hooks/pre-commit`. If the hook is empty or does not exist, you must run the project's tests manually to ensure code integrity.

---

## II. Coding & Output Standards (Context-Dependent)

**Check the Context**: Is the user asking for help with a **Homework/Problem Set** or a **Professional/Research Project**?

### Context A: Professional, Research & Default
*Trigger: Default case (Research, Dev, Engineering).*

- **Goal**: High-quality Industry Standard Engineering.
- **Code Style**:
  - **Structure**: Modular, robust, and scalable. Use classes, functions, and proper abstractions.
  - **Commenting**: Use comments according to industry standards. You may use comments during the drafting phase for internal reasoning or step tracking, but you must clean them up before final delivery. Final comments should be minimal, focusing on the "why" rather than the "how," and should follow standard docstring practices.
  - **Best Practices**:
    - Use Type Hinting (`typing`) where helpful.
    - **Error handling**: Only catch exceptions you can concretely handle. Never silently swallow exceptions. If catching to add context, always re-raise (`raise ... from e`). If catching at a boundary for logging, log then re-raise (`raise`). A bare `except: pass` or catching broadly and continuing as if nothing happened is always wrong — it creates silent bugs that are harder to debug than the original exception.
    - Follow PEP 8 standards.
  - **Performance**: Optimize for speed and memory efficiency (especially for ML/Data tasks).
  - **Git / Commits**:
    - **Convention**: Use Conventional Commits (`feat:`, `fix:`, `chore:`, etc.).
    - **Casing**: **Strictly use lowercase** for the subject description (e.g., `feat: add new layer`, NOT `feat: Add new layer`).
    - **Co-authors**: **Never add Claude as co-author in commits.** Do not include `Co-Authored-By: Claude ...` lines in any commit messages. Always commit with only human authors.
  - **Test Organization (REQUIRED)**:
    - **MUST**: Place all test files in a `tests/` directory that **exactly mirrors** the `src/` structure.
      - `src/utils/helper.py` → `tests/utils/test_helper.py`
      - `src/models/user.py` → `tests/models/test_user.py`
      - `src/api/endpoints/auth.py` → `tests/api/endpoints/test_auth.py`
    - **File Naming**: All test files **must** be prefixed with `test_` (e.g., `test_helper.py`, `test_auth.py`).
    - **Directory Structure**: Create directories in `tests/` to match `src/` hierarchy. Do not flatten test files into a single directory.
    - **Violations**: If you create test files outside this structure, fix the organization before committing. Do not merge PRs or commit code with disorganized tests.
- **Writing Tone**:
  - **Tone**: Academic (ML, Physics or Chemistry papers at high quality journals), technical, and concise. Avoid the "AI accent" (e.g., avoid "It is worth noting," "In conclusion," "Let's delve into," or "I have successfully..."). The quality should match a seasoned author published in Nature or Science.
  - **Vocabulary**: Use simple but precise technical language. Avoid overly complex synonyms when simpler ones work (e.g., use "use" instead of "utilize," "fix" instead of "rectify," "show" instead of "demonstrate").
  - **Style**: Focus on direct technical communication. Use active voice where appropriate for clarity but maintain the rigorous objectivity expected in top-tier journals.
  - **Punctuation**: Never use the EM dash.

### Context B: Educational & Learning-Focused Work
*Trigger: prompts mentioning "pset", "homework", "class", "assignment", or academic coursework.*

- **Code Style**:
  - **Structure**: Keep scripts simple and linear (script-based). Avoid complex classes or patterns unless explicitly asked.
  - **Readability**: Prioritize basic clarity over clever optimization.
  - **Comments**: Sparse. Only explain *why* a tricky step was taken. Do not narrate syntax.
- **Writing Tone**:
  - **Tone**: Use a direct, first-person or neutral academic voice. Avoid the "AI accent" (e.g., avoid phrases like "It is worth noting," "In conclusion," "A comprehensive analysis reveals," or "delve into").
  - **Vocabulary**: Use simple, clear, and unpretentious language. Do not use complex synonyms when a simple word works better (e.g., use "use" instead of "utilize").
  - **Content**: Be explicit in your explanations. Fully explain reasoning and derivation in accessible terms.
  - **Structure**: Answer the question directly. Do not add fluff or filler sentences.
  - **Punctuation**: Never use the EM dash.
