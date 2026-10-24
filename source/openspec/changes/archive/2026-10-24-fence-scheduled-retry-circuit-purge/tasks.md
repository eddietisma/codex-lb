## Verification

- [x] Reproduce races before implementation. Eleven regressions fail and three controls pass.
- [x] Fence timestamp, generation, failure count, and nullable detail without changing retention rules.
- [x] Verify all 14 purge regressions on SQLite and 107 combined purge/retention/lifecycle tests.
- [x] Verify the scheduled race suite against disposable PostgreSQL.
- [x] Run focused lint, format, typing, and strict OpenSpec validation before archive.
