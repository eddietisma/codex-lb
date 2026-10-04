## Why

An account-neutral model-transition fork returns the parent's turn-state token. The next turn resolves the parent again, repeats the owner conflict and opens another upstream connection.

## What changes

Allocate a fresh response turn-state token before HTTP headers are sent when the incoming durable token belongs to an incompatible model. Register that token on the child session without changing the parent alias. Preserve forwarded tokens and compatible-model reuse.

## Impact

HTTP response bridge session continuity. No schema or configuration changes.
