## ADDED Requirements

### Requirement: Bootstrap discovery recognizes GPT-6.1 Sol

The bootstrap catalog MUST include `gpt-6.1-sol` with a 500,000-token default
context window, an 872,000-token maximum context window, minimum client version
`0.153.0`, and Code Mode metadata. The local Codex-native catalog MUST apply its
existing Lite override to this entry. Refreshed model catalogs, API-key
restrictions, and authoritative model suppression MUST retain precedence.

#### Scenario: Client discovers models before the first refresh

- **GIVEN** the live registry has no snapshot
- **WHEN** a client requests a Codex-native model catalog
- **THEN** GPT-6.1 Sol is present with its default and maximum context windows
- **AND** the entry reports `use_responses_lite: false` and `tool_mode: code_mode_only`

#### Scenario: Upstream metadata supersedes bootstrap values

- **GIVEN** a successful refresh supplies GPT-6.1 Sol metadata
- **WHEN** a client discovers models
- **THEN** refreshed metadata supersedes the bootstrap entry
