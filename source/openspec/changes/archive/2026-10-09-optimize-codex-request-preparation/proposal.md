# Optimize Codex request preparation

## Why
Large Codex histories incur repeated payload conversion, eager unsafe-replay serialization, nested copies and quadratic compaction work. Synthetic measurements showed approximately 19 ms per full payload conversion, 26 ms for retry serialization, 45 ms for slimming, and seconds for long-history compaction.

## What Changes
Implement seven independent source commits directly on main, preserving request contents, quota estimates, replay eligibility, tool pairing, omission markers and wire budgets. Investigate premature stream closures separately; change recovery only for a confirmed defect. Pin Compose to the validated source commit in a separate deployment commit, push the stack, build and restart only the app.

## Validation
Run existing WebSocket preparation, API-key usage, slimming and compaction coverage. Add regression coverage for skipped work, input immutability, duplicate tool IDs and exact wire-size parity where needed. Compare compaction and request preparation against the previous source using deterministic synthetic inputs. Validate OpenSpec, lint and typing. Before deployment verify bind mounts, back up PostgreSQL, and record account/API-key identities. After restart verify image revision, readiness, dashboard and identity preservation.
