## ADDED Requirements

### Requirement: Generate controls do not create replay ownership

The account-neutral fresh-replay classifier MUST accept an optional boolean `generate` control without assigning account ownership solely because that control is present. Replay MUST preserve its exact boolean value. Non-boolean values MUST remain ineligible for account-neutral replay. Existing response-anchor, file-owner, unknown-field and tool-safety restrictions MUST remain enforced.

#### Scenario: Prewarm quota rejection on the first account

- **GIVEN** a self-contained unanchored WebSocket request with `generate: false` and a healthy replacement account
- **WHEN** the first account rejects the request before response creation because its quota is exhausted
- **THEN** the proxy retries on the healthy account with `generate: false` intact
- **AND** it does not emit an owner-unavailable error solely because of the generate control

#### Scenario: Account-bound input stays on its owner

- **GIVEN** a request contains an account-owned file or an upstream response anchor
- **WHEN** it also contains a boolean generate control
- **THEN** the generate control does not permit moving the request to a different account
