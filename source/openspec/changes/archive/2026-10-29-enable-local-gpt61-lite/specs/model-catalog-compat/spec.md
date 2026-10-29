## RENAMED Requirements

- FROM: `### Requirement: Local GPT-6.1 Sol catalog disables Lite`
- TO: `### Requirement: Local GPT-6.1 Sol catalog enables Lite`

## MODIFIED Requirements

### Requirement: Local GPT-6.1 Sol catalog enables Lite

This local deployment MUST report `use_responses_lite: true` for the
`gpt-6.1-sol` entry in Codex-native model catalogs, regardless of the upstream
flag. It MUST preserve other model metadata, other model entries, and the
upstream registry's Lite value. Existing request serialization MUST remain
unchanged.

#### Scenario: GPT-6.1 Sol has upstream capability metadata

- **GIVEN** upstream reports `gpt-6.1-sol` with either value of `use_responses_lite`
- **WHEN** a client requests a Codex-native model catalog
- **THEN** the entry reports `use_responses_lite: true`
- **AND** upstream registry metadata remains unchanged

#### Scenario: Other models retain their advertised capabilities

- **GIVEN** upstream reports another model with either value of `use_responses_lite`
- **WHEN** a client requests a Codex-native model catalog
- **THEN** that model retains its upstream `use_responses_lite` value

### Requirement: Bootstrap discovery recognizes GPT-6.1 Sol

The bootstrap catalog MUST include `gpt-6.1-sol` with a 500,000-token default
context window, an 872,000-token maximum context window, minimum client version
`0.153.0`, and Code Mode metadata. The local Codex-native catalog MUST report
`use_responses_lite: true` for this entry. Refreshed model catalogs, API-key
restrictions, and authoritative model suppression MUST retain precedence.

#### Scenario: Client discovers models before the first refresh

- **GIVEN** the live registry has no snapshot
- **WHEN** a client requests a Codex-native model catalog
- **THEN** GPT-6.1 Sol is present with its default and maximum context windows
- **AND** the entry reports `use_responses_lite: true` and `tool_mode: code_mode_only`

#### Scenario: Upstream metadata supersedes bootstrap values

- **GIVEN** a successful refresh supplies GPT-6.1 Sol metadata
- **WHEN** a client discovers models
- **THEN** refreshed metadata supersedes the bootstrap entry except for the local Lite opt-in
