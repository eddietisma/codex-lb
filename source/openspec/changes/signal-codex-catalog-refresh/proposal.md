# Signal the gateway model catalog to Codex

## Why

The desktop can resume a thread with unknown-model fallback metadata even though
the gateway's remote catalog parses successfully. The gateway currently omits
the model catalog entity tag and the client's supported `x-models-etag`
discovery signal on response connections.

## What changes

- Give Codex-native catalogs content-based entity tags.
- Advertise the same scoped catalog tag on response WebSocket handshakes and
  backend HTTP response streams.
- Preserve catalog restrictions and existing response payloads.
