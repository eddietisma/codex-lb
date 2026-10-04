## Why

Codex sends `generate: false` for prewarm requests. The fresh-replay classifier rejects this known request control as an unknown field and binds an otherwise self-contained request to the initially selected account. If that account exhausts its quota, reconnect selection returns an owner-unavailable error instead of using a healthy account.

## What changes

Accept an explicitly boolean `generate` control in account-neutral fresh replay and preserve its value on retry. Continue rejecting malformed controls, stored response anchors, file owners and unknown fields.

## Impact

Fresh Responses WebSocket failover and shared replay classification. No settings or schema changes.
