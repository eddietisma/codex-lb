## Operator diagnostic

`websocket_full_history_replay` is a warning emitted when an anchored request installs a retained full-history body. `stage=prepared` identifies a recovery attempt, not proof of upstream dispatch or successful completion. The request id joins the event to existing account-selection messages and request-log outcomes.

Conversation, session, previous-response and previous-owner identifiers use the existing hashed-reference format. Repeated warnings with the same conversation hash expose repeated recovery attempts across requests. The event includes the input-item count, current replay count, account-neutral classification and whether the replay releases the owner pin. It contains no prompt or history text and no credentials. Routing, retry limits and ownership checks are unchanged.

## Validation on 2026-10-29

- The native quota-recovery assertions failed before the warning was added and passed afterward for both selection-time and upstream quota failures.
- The 15-case focused suite verifies the warning fields and hashing, rejects warnings for encrypted context that cannot replay, and completes two later incremental messages without another warning. The replacement receives input-item counts of 3, 2 and 1 over those three requests.
- All 183 native WebSocket, generate-failover and quota-owner integration tests passed.
- All 103 selected previous-response, account-switch and fresh-replay unit tests passed.
- Ruff lint, formatting, targeted type checking, strict OpenSpec change validation and `git diff --check` passed.
