---
name: tdd-workflow
description: "Step-by-step TDD process for ML research and infrastructure: RED-GREEN-REFACTOR cycle with git checkpoints, mandatory failing-test validation, and ML-specific test patterns. Activate when implementing new features, refactoring logic, or adding new model/data components."
origin: affaan-m/everything-claude-code (adapted for ML)
---

# TDD Workflow for ML Research & Infrastructure

## When to Activate

- Implementing a new feature, model component, data pipeline, or utility
- Refactoring or restructuring existing logic
- Fixing a bug in core logic (write a regression test that reproduces it first)
- Adding a new training objective, evaluation metric, or data transform

---

## Step 1: Specify Behavior

Before writing any test or code, write down (in a comment or docstring) what the unit should do:
- Input/output contract
- Edge cases (empty batch, single element, dtype mismatch)
- Shape invariants for tensor-returning code (e.g., `# (B, T, D) -> (B, D)`)

---

## Step 2 (RED): Write Failing Tests

Write tests **before** touching production code. All three levels are required for non-trivial features:

**Unit** — single function or class in isolation:
```python
def test_attention_mask_excludes_padding():
    mask = build_padding_mask(lengths=torch.tensor([3, 5]), max_len=8)
    assert mask.shape == (2, 8)
    assert mask[0, 3:].all()   # padding positions masked
    assert not mask[0, :3].any()  # valid positions unmasked
```

**Integration** — components working together:
```python
def test_encoder_respects_padding_mask(small_batch):
    encoder = Encoder(hidden=64, heads=4)
    out = encoder(small_batch["input_ids"], mask=small_batch["mask"])
    # padding positions should produce near-zero output
    pad_pos = small_batch["mask"].bool()
    assert out[pad_pos].abs().max() < 1e-3
```

**Shape / overfit sanity** — ML-specific regression guards:
```python
@pytest.mark.parametrize("B,T", [(1, 1), (4, 128), (16, 512)])
def test_forward_output_shape(B, T):
    model = MyModel(vocab=100, hidden=64)
    out = model(torch.randint(0, 100, (B, T)))
    assert out.shape == (B, T, 100)   # document expected shape inline

def test_loss_decreases_on_tiny_batch():
    model = MyModel(vocab=10, hidden=32)
    optim = torch.optim.Adam(model.parameters(), lr=1e-2)
    x = torch.randint(0, 10, (2, 8))
    losses = [run_step(model, optim, x) for _ in range(20)]
    assert losses[-1] < losses[0], "loss did not decrease"
```

---

## Step 3: Confirm RED State

Run the tests **and verify they fail for the right reason** (missing implementation, not a syntax error or import failure):

```bash
pytest tests/path/to/new_test.py -v
# Expected: FAILED — not ERROR
```

If any test errors instead of fails, fix the test scaffolding before continuing. Do not proceed to Step 4 until all new tests show `FAILED`.

**Git checkpoint after RED validation:**
```bash
git add tests/
git commit -m "test: add failing tests for <feature>"
```

---

## Step 4 (GREEN): Write Minimal Implementation

Write the **minimum** code to make the tests pass. No premature optimization, no extra features.

Rules during GREEN:
- No new tests
- No refactoring
- No performance work
- Aim for correctness only

```bash
pytest tests/path/to/new_test.py -v
# Expected: PASSED
```

**Git checkpoint after GREEN:**
```bash
git add src/
git commit -m "feat: implement <feature> (tests passing)"
```

---

## Step 5: Verify Full Suite Passes

Run the full test suite to catch regressions:
```bash
pytest -m "not slow and not gpu" -x
```

Fix any regressions before moving to Step 6.

---

## Step 6 (REFACTOR): Improve Code Quality

With a green test suite as a safety net, refactor for:
- Clarity (naming, structure, docstrings)
- Elimination of duplication (extract if pattern appears 3+ times)
- Performance (only if profiled — no premature optimization)
- Type hint completeness

Re-run tests after every meaningful change:
```bash
pytest -m "not slow and not gpu" --tb=short
```

**Git checkpoint after REFACTOR:**
```bash
git add -p   # stage only refactoring changes
git commit -m "refactor: clean up <feature> implementation"
```

---

## Step 7: Verify Coverage

```bash
pytest --cov=src --cov-report=term-missing --cov-fail-under=80
```

Target: **80%+ overall**, **100% on critical paths** (loss functions, data transforms, metric computations). If below 80%, add targeted tests for uncovered branches before considering the task done.

---

## ML-Specific Rules

- **Synthetic data only** in tests — never load real datasets or checkpoints.
- **Test shapes, not exact floats** — use `pytest.approx` with tolerance only when the value is analytically known.
- **GPU tests are opt-in**: mark `@pytest.mark.gpu` and guard with `@pytest.mark.skipif(not torch.cuda.is_available(), ...)`.
- **Slow tests are opt-in**: mark `@pytest.mark.slow` for anything > ~5 seconds.
- Always document tensor shapes in test assertions: `assert out.shape == (B, T, D)  # (batch, seq, hidden)`.

---

## Quick Reference

| Stage | Action | Verification |
|-------|--------|-------------|
| RED | Write tests | `pytest` shows `FAILED` (not ERROR) |
| GREEN | Write minimal impl | `pytest` shows `PASSED` |
| REFACTOR | Improve code | `pytest` still `PASSED` |
| COVERAGE | Check 80%+ | `pytest --cov --cov-fail-under=80` |
