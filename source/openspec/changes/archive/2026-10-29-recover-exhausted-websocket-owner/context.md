## Behavior

A previous-response identifier belongs to the account that created it. Sending that identifier to another account cannot preserve continuity. When the proxy already retained a verified account-neutral full resend, it can remove the identifier and send the complete history through ordinary account selection.

Previously, reconnect selection returned the exhausted owner's failure before considering that retained body. Pre-created quota replay also excluded verified client-provided full resends from the account-switch path. Both paths now use the existing fresh-replay classifier and preserve explicit turn-state, file, and raw legacy ownership. The sender uses the prepared request state's body so reconnect recovery cannot accidentally dispatch the old anchored text.

For example, if account A exhausts quota after a chat's last response and account B has quota, a verified full resend can complete through B without exposing A's intermediate failure. A delta-only continuation remains with A because the proxy does not have the missing history.

## Source validation on 2026-10-29

- Regression reproduced through the native WebSocket route before the fix.
- 220 integration tests passed across native WebSocket responses, generate failover, sticky routing, and the new quota-owner suite. One unrelated HTTP goal-restart scope test was excluded after timing out on both the candidate and unchanged base `b7d04cdc`.
- 351 selector and soft-sticky unit tests passed.
- The new route suite includes both native endpoints, selection-time exhaustion, pre-created quota rejection, the real load balancer and persisted usage, an empty replacement pool, delta-only history, file pins, explicit turn-state ownership, and orphan tool output.
- Targeted Ruff lint, Ruff formatting, type checking, and `git diff --check` passed.
- Strict validation of this OpenSpec change passed. Normal validation of all 68 existing specifications passed. Repository-wide strict mode reports existing requirement-length warnings, including in untouched specifications.

The integration run used `--rootdir=tests --confcutdir=tests --import-mode=importlib` because pytest's default root scan encounters an inaccessible `.claude` link on this Windows checkout. Test logs remain under `E:/.tmp/20261029-codexlb-quota-*`.

## Deployment on 2026-10-29

The local Docker deployment runs `codex-lb:quota-owner-c617610a`, built from source revision `c617610a8abefc36ed70680ef345f0658b5f6230`. Both changed production modules matched their packaged SHA-256 hashes before rollout. The service restarted through its normal shutdown drain, and `/health/ready` returned `status: ok` with `database: ok`.

A live native Responses WebSocket smoke request completed with output `OK` under isolated diagnostic session `quota-failover-deploy-smoke-a0e6cc7188df4e788e1b63f5247cd5ae`. Automatic exhausted-owner recovery is covered by the route regressions and the real-selector integration test above; this live smoke confirms ordinary inference through the deployed image.
