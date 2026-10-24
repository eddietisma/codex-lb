## Why

This deployment needs to redirect selected model names while retaining access
to all other models. An API-key enforced model would replace every request.
Redirects must be explicit and default empty because model availability and
the operator's intended substitutions differ between deployments.

## What Changes

- Add `CODEX_LB_MODEL_REDIRECTS`, a JSON object of exact model names to targets.
- Apply configured redirects through shared model normalization and model
  allowlist canonicalization, including original chat payload forwarding.
- Preserve reasoning effort, service tier, and existing API-key enforcement.
- Reject blank/non-string entries and targets that are also redirect sources.

## Capabilities

### Modified Capabilities

- `responses-api-compat`: Explicit deployment model redirects.

## Impact

Settings, request policy, focused tests, and generated settings reference.
No database, dependency, dashboard, or account policy changes.
