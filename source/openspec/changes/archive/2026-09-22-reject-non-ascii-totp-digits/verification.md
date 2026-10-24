# Verification

Adapted from Soju06/codex-lb PR #2487 at
`175d8c3a179f4d7518d12f6efc24676254b1aa40`, by Amin and Soju06.

Local verification on 2026-10-24:

- Before the fix, eight Unicode unit/HTTP cases failed with `TypeError`; 15 controls passed.
- After the fix, the TOTP unit and dashboard HTTP suites passed all 23 tests.
- The combined TOTP and account-selection regression run passed 427 tests.
- Focused Ruff lint/format and typing checks passed.
- Strict OpenSpec validation passed all 68 main specifications.

The implementation changes only digit normalization. Comparison, time windows,
formatted ASCII codes, enrollment state, and replay protection retain coverage.
