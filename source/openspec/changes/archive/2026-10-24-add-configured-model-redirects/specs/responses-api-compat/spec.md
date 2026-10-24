## ADDED Requirements

### Requirement: Explicit deployment model redirects

The proxy MUST accept `CODEX_LB_MODEL_REDIRECTS` as a JSON object of exact,
case-sensitive source model names to target model names, defaulting to an empty
mapping. Keys and values MUST be nonblank strings. Invalid objects and mappings
whose targets are also source keys MUST fail configuration validation.

#### Scenario: Disabled or invalid configuration

- **WHEN** redirects are unset or empty
- **THEN** existing model behavior is unchanged
- **WHEN** configuration contains blank or non-string entries, chains, or cycles
- **THEN** settings validation rejects it

### Requirement: Redirected requests preserve request controls

Configured source names MUST resolve to their target in shared request model
normalization, model allowlist canonicalization, and original chat payload
forwarding. A redirect MUST preserve the request's reasoning effort and service
tier. Unmapped model names MUST retain existing behavior. Redirects
MUST be single-hop and MUST NOT infer model suffixes or wildcard matches.

#### Scenario: Selected model substitution

- **GIVEN** redirects for `gpt-6-astra`, `gpt-6-sol`, and `gpt-6-luna` to `gpt-6.1-sol`
- **WHEN** a client requests one of those exact names with high reasoning and priority service
- **THEN** the outgoing model is `gpt-6.1-sol` with the requested reasoning and tier
- **AND** requesting another model preserves its existing model behavior

### Requirement: Redirects retain API-key policies

Existing API-key model, reasoning, and tier policies MUST remain authoritative
after redirect resolution. Model allowlists MUST compare source and target
model names using shared canonicalization.

#### Scenario: Model allowlists and enforced policies

- **WHEN** an API key allows a redirected source or its target
- **THEN** access checks compare their shared target
- **AND** an unrelated allowed model does not authorize the redirected model
- **AND** enforced model, reasoning, and tier policies continue to apply
