## 1. Implementation

- [x] 1.1 Add validated default-empty exact model redirect configuration.
- [x] 1.2 Apply redirects to model normalization, allowlists, and chat forwarding.
- [x] 1.3 Register setting metadata and regenerate the settings reference.

## 2. Verification

- [x] 2.1 Cover redirects, unchanged models, reasoning/tier, and key policies.
- [x] 2.2 Run focused tests, lint, settings checks, and strict OpenSpec validation.
- [x] 2.3 Sync requirements and archive the verified change.

Focused verification passed 174 tests, Ruff, Ty, settings tier coverage, and
strict change validation. Whole-tree strict spec validation reports warnings
in 60 existing specs and zero errors. The change adds no such warnings.

Another 38 integration cases passed across HTTP Responses, chat completions,
compaction, the HTTP session bridge, and WebSocket Responses. Requests for
unmapped GPT-6.1 Sol and GPT-5.6 Sol retain their original models. Redirected
requests pass authorization with a target-only model allowlist.
