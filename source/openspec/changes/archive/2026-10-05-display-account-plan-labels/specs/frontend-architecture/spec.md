## ADDED Requirements

### Requirement: Local account plan display names

The dashboard MUST display the internal account plan identifier `pro` as `Pro 200` and `prolite` as `Business Premium` in account, dashboard and API-key account displays. Other plan labels MUST retain their existing formatting. Display names MUST NOT change persisted plan identifiers, quota capacities, routing or model eligibility.

#### Scenario: Display and search the local plan label

- **GIVEN** an account has plan type `prolite`
- **WHEN** its plan is displayed or searched by display name
- **THEN** its displayed plan name is `Business Premium`
- **AND** its internal plan type remains `prolite`

#### Scenario: Display the Pro 200 plan

- **GIVEN** an account has plan type `pro`
- **WHEN** its plan is displayed or searched by display name
- **THEN** its displayed plan name is `Pro 200`
- **AND** its internal plan type remains `pro`
