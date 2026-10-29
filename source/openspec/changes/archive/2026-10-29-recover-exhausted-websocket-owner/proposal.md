## Why

WebSocket reconnect selection can reject an exhausted previous-response owner before the proxy uses its retained, verified full-history resend. A chat then reports a usage limit even when another eligible account has quota.

## What Changes

- Retry account selection with the verified account-neutral full-history body when its previous-response owner has exhausted quota.
- Apply the same recovery to quota rejections received before a response becomes visible.
- Keep file ownership, explicit turn-state ownership, incomplete history, and authenticated routing constraints authoritative.
- Retain the existing attempt limits, request budget, and reservation lifecycle.

## Capabilities

### Modified Capabilities

- `sticky-session-operations`: Recover exhausted previous-response owners through verified fresh replay.

## Impact

- Native Responses WebSocket selection and pre-created quota replay.
- Route regression tests and the sticky-session operation specification.
