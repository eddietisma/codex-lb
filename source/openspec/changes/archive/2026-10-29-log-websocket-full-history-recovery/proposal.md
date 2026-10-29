## Why

Operators need to identify repeated full-history recovery attempts for the same conversation without inspecting conversation content. The current reconnect message contains no stable conversation identifier and does not cover the shared fresh-replay path.

## What Changes

- Emit one warning when an anchored WebSocket request installs a retained full-history body for recovery.
- Include the request id, hashed conversation/session/owner/anchor identifiers, input-item count, and replay state.
- Keep ordinary incremental continuations silent and leave routing behavior unchanged.

## Capabilities

### Modified Capabilities

- `proxy-runtime-observability`: Add a correlatable full-history recovery diagnostic.

## Impact

- WebSocket fresh-replay preparation and route-level logging regressions.
