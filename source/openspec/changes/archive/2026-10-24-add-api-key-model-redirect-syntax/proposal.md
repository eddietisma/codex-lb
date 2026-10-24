## Why

Operators need to see and edit selective model redirects on API keys in the
dashboard. Deployment-only redirects are invisible in the key editor, while a
plain enforced model replaces every requested model.

## What changes

- Accept exact `source:target` rules in the existing enforced model field.
- Accept comma-separated rules for several source models on one key.
- Retain plain model names as unconditional enforcement.
- Show the syntax and saved policy in the API key dashboard.
- Preserve unmapped requests, allowlists, reasoning and service-tier policy.

## Capabilities

### Modified capabilities

- `api-keys`: Conditional enforced model syntax and dashboard visibility.
- `responses-api-compat`: Consistent selective enforcement across proxy routes.

## Impact

No new database columns, dependencies, or environment settings. Existing bare
model policies keep their behavior. This deployment will move the three GPT-6
redirects onto its existing `codex` key.
