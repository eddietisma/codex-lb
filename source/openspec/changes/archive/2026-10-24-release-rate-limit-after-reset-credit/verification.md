## Local adoption, 2026-10-24

Adapted from upstream PR #2640, head 46f6e954472fa3f3337a4c25bb036829d5f9cf2e. Both real consume API regressions failed before the patch: the upstream-confirmed reset left the account RATE_LIMITED despite available quota and a changed weekly deadline.

After the patch, 258 affected tests passed on Windows with isolated SQLite. The same affected suites passed 242 tests in the Linux regression image against a disposable PostgreSQL 18 database. The PostgreSQL run excluded the existing SQLite-only direct-claim tests in test_reset_credits_replica_safety.py: those invoke a documented SQLite claim helper that uses sqlite_insert unconditionally. An initial broad PostgreSQL attempt reached 44 passing tests and five such SQLite-claim failures before interruption. No production database was used.

The PostgreSQL cases cover the accounts API, dashboard API, automatic redemption, failed-baseline transaction isolation, concurrent 429 and usage-refresh evidence, ambiguous windows, non-reset outcomes, and still-exhausted quota. Scoped Ruff check/format, Ty, proxy timing seams, strict scoped change validation and all 68 canonical specifications passed. The canonical usage-refresh-policy requirement is synchronized.

The status update still compares the expected status, reset_at and blocked_at. A concurrent later 429 therefore cannot be cleared by stale redemption evidence. The bypass requires a confirmed reset and evidence that exactly the blocked quota window moved; uncertain cases retain the cooldown. No live provider redemption or deployment is claimed.