## Why

The operator requested `use_responses_lite: true` in the local CodexLB model
catalog. The existing GPT-6.1 Sol override forces the flag off even when upstream
enables it. This change enables Lite without changing other models or attempting
to fix the separate unsupported-tool rejection.

## What changes

- Advertise Lite for the local GPT-6.1 Sol entry, including bootstrap discovery.
- Preserve upstream registry metadata and other model capabilities.
- Retain the existing handling of explicitly standard requests with historical
  Lite bundles.

## Impact

- Affects Codex-native model catalog responses and their regression tests.
- Requires a catalog refresh in Codex clients.
- Does not guarantee that an incompatible tool definition will work with Lite.
