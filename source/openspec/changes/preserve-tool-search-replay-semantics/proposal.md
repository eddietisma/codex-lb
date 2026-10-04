# Why

Completed client-executed tool-search calls and outputs carry discovered tool declarations. Dropping those pairs from an otherwise account-neutral failover loses the schemas the replacement account needs.

# What changes

Preserve self-contained client-owned pairs whose discovered function, custom and grouped namespace declarations satisfy existing account-neutral rules. Reject server-owned, failed, malformed, hosted, MCP and container-bound state. Strip response-owned item IDs before fresh HTTP bridge and WebSocket retries and retain untrimmed history for full resend.

# Scope

The surrounding request must already satisfy the existing owner-loss replay proofs. This change does not broaden top-level declared-tool allowlists, change compaction-trigger validation, modify model-source capabilities, or relax account/file ownership.

# Capabilities

## Modified capabilities

- `responses-api-compat`: retain validated client-owned tool-search pairs through proven fresh replay.