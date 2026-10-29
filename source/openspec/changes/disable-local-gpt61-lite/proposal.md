# Disable Lite in the local GPT-6.1 Sol catalog

## Why

The local Codex client receives Responses-Lite tool rejection errors for
`gpt-6.1-sol`. The operator requested a catalog override to test the standard
Responses request format. This is a local workaround, not a confirmed root-cause
fix.

## What changes

- Report `use_responses_lite: false` for `gpt-6.1-sol` at the Codex catalog boundary.
- Preserve the upstream registry, other model metadata, and request forwarding.

## Impact

- Affects `model-catalog-compat` and the local deployment.
- Clients must reload their model catalog. Existing Lite requests remain supported.
