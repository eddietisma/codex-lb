# Normalize GPT-6.1 Sol history after disabling Lite

## Why

The catalog override does not remove historical `additional_tools` items from
existing threads. CodexLB detects those items and enables Lite even when the
client sends current tools at the standard top level. A live mixed-format request
reproduced the reported rejection; the same request without the historical bundle
completed successfully.

## What changes

- For local `gpt-6.1-sol` requests with explicit top-level tools, omit obsolete
  `additional_tools` input items during wire serialization.
- Preserve current tools, all other history items, the original request object,
  and Lite requests that omit top-level tools.

## Impact

- Affects `model-catalog-compat`, request serialization, and the local deployment.
