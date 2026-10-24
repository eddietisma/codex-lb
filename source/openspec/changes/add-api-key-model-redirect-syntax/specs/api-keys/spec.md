## ADDED Requirements

### Requirement: Conditional enforced model syntax

The API key `enforcedModel` field MUST accept a plain model name to force every
request, or comma-separated exact `source:target` rules to replace only matching
requested models. Rule separators MAY have surrounding whitespace. The system
MUST reject empty sides, duplicate sources, chains, cycles, and mixtures of bare
model names and rules. Each target MUST be permitted by a configured allowlist.

#### Scenario: Selective model replacement

- **GIVEN** `enforcedModel` is `gpt-6-sol:gpt-6.1-sol`
- **WHEN** the key requests `gpt-6-sol`
- **THEN** the effective model is `gpt-6.1-sol`
- **AND** requesting another model retains that requested model

#### Scenario: Existing unconditional enforcement

- **GIVEN** `enforcedModel` is the plain name `gpt-6.1-sol`
- **WHEN** the key requests any model
- **THEN** existing unconditional enforcement remains effective

### Requirement: Dashboard model policy visibility

Create and edit dialogs MUST explain plain model enforcement and `source:target`
syntax. The key list MUST show the saved enforced model policy. Editing and
saving a conditional policy MUST preserve its rules.

#### Scenario: Review and edit redirects

- **WHEN** the operator views a key with saved conditional rules
- **THEN** the list and edit dialog show those rules
- **AND** the dialog explains how to enter several comma-separated rules
