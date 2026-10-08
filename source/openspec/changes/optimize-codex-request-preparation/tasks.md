## Separate source commits
- [x] Read the service tier directly instead of dumping the request.
- [x] Check fresh-replay safety before serializing a fallback body.
- [x] Skip quota payload dumps for previous-response/conversation context.
- [ ] Reuse the normalized body after stripping capability metadata.
- [ ] Copy only changed history nodes during oversized payload slimming.
- [ ] Precompute compaction tool matches without changing pairing semantics.
- [ ] Track exact compaction wire size incrementally.

## Verification and delivery
- [ ] Investigate premature stream closures and record whether a defect is confirmed.
- [ ] Pass relevant compatibility tests, lint, typing and OpenSpec checks.
- [ ] Measure synthetic performance against the previous source.
- [ ] Back up PostgreSQL and verify existing data mounts and identities.
- [ ] Pin Compose in a separate deployment commit and push main.
- [ ] Build, restart and verify the deployed revision and readiness.
