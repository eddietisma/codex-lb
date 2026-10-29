## ADDED Requirements

### Requirement: Local GPT-6.1 Sol catalog disables Lite

This local deployment MUST report `use_responses_lite: false` for the
`gpt-6.1-sol` entry in Codex-native model catalogs. It MUST preserve other
model metadata, other model entries, and the upstream registry's Lite value.
It MUST continue forwarding existing Lite requests without changing their format.

#### Scenario: Upstream enables Lite for GPT-6.1 Sol

- **GIVEN** upstream reports `gpt-6.1-sol` with `use_responses_lite: true`
- **WHEN** a client requests a Codex-native model catalog
- **THEN** the entry reports `use_responses_lite: false`
- **AND** upstream registry metadata remains unchanged

#### Scenario: Other models retain their advertised capabilities

- **GIVEN** upstream reports another model with `use_responses_lite: true`
- **WHEN** a client requests a Codex-native model catalog
- **THEN** that model retains `use_responses_lite: true`
