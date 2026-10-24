# Hard continuity owner backoff

A request with a resolved owner cannot move to another account. Selecting only
that active owner currently loses the ordinary transient-backoff fallback,
because its conditions inspect other accounts in the pool. Explicit owner-pool
evidence permits the existing fallback while preserving earlier eligibility
filters. Soft sticky preferences retain their existing fallback behavior.

For example, an active owner with five errors and a last error one minute ago
must still serve its anchored request. A paused owner must remain unavailable.

Local validation on 2026-10-24:

- Before implementation, the required-owner contract regression returned
  `continuity_owner_unavailable` for an active backed-off owner. Eight of the
  nine added cases failed before the new flag existed; the paused-owner
  contract control already passed.
- All 404 tests in the three affected account-selection modules passed after
  implementation. Combined with the TOTP suites, 427 tests passed.
- Focused Ruff lint/format and typing checks passed.
- Strict validation of all 68 main specifications passed before syncing this
  delta; the change and synced specifications are validated before archival.
