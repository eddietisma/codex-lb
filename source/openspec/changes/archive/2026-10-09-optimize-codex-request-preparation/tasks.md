## Separate source commits
- [x] Read the service tier directly instead of dumping the request.
- [x] Check fresh-replay safety before serializing a fallback body.
- [x] Skip quota payload dumps for previous-response/conversation context.
- [x] Reuse the normalized body after stripping capability metadata.
- [x] Copy only changed history nodes during oversized payload slimming.
- [x] Precompute compaction tool matches without changing pairing semantics.
- [x] Track exact compaction wire size incrementally.

## Verification and delivery
- [x] Investigate premature stream closures and record whether a defect is confirmed.
- [x] Preserve sanitized native receive-failure categories in operator logs without changing replay or public errors.
- [x] Pass relevant compatibility tests, lint, typing and OpenSpec checks, with the four confirmed baseline proxy-environment failures recorded in context.
- [x] Measure synthetic performance against the previous source.
- [x] Back up PostgreSQL and verify existing data mounts and identities.
- [x] Pin Compose in a separate deployment commit and push main.
- [x] Build, restart and verify the deployed revision and readiness.
