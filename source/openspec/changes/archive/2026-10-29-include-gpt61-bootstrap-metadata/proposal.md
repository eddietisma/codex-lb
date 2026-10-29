# Include GPT-6.1 Sol in bootstrap discovery

## Why

The live catalog includes GPT-6.1 Sol, but the server's bootstrap catalog does
not. A client discovering models before refresh or after registry clear can
treat this model as unknown and fall back to a 272,000-token ceiling. A local
client catalog avoids that failure but disables live discovery.

## What changes

- Add GPT-6.1 Sol metadata to the existing server bootstrap catalog using the
  verified upstream values captured on 2026-10-29.
- Preserve refreshed catalog precedence, plan gating, and suppression behavior.
- Remove the operator's temporary client-side catalog override after deployment.

## Impact

- Affects `model-catalog-compat` and model bootstrap discovery.
