## Why

The inherited client full-resend classifier accepts structurally self-contained input with an unknown previous response. That does not prove the input contains the previous response's complete context. Using it to release a client-supplied anchor on quota exhaustion can silently omit history.

## What Changes

- Keep client-supplied previous responses owner-bound during quota recovery.
- Retain automatic recovery only for anchors the proxy inserted into an originally unanchored, retained account-neutral request.
- Test real reconnects with known prior history, and reject incomplete unknown-anchor input.

## Capabilities

### Modified Capabilities

- `sticky-session-operations`: Narrow quota replay to proxy-owned anchors.

## Impact

- Native WebSocket quota replay and regression coverage.
