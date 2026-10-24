# Local adaptation

Adapted from Soju06/codex-lb PR #2280 at `17e1dce17a71203596f21ef38f7347a1ec373182`.
The production change adds conditional-delete comparisons for the selected
observation and stops the current purge pass after a changed row is spared.
No schema or configuration changes are required.

Local SQLite verification on 2026-10-24 reproduced eleven failures before the
fix and passed all fourteen purge regressions afterward. The combined purge,
retention scheduler, and bridge lifecycle suites passed 107 tests.

All ten scheduled-purge integration cases also passed against a dedicated disposable PostgreSQL 18 container. Focused Ruff lint/format and typing passed. The upstream author is Yannic Charlon.
