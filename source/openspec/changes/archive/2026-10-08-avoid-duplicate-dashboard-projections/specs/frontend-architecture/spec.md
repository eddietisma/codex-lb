## ADDED Requirements

### Requirement: Depletion-only projection polling

The projections endpoint SHALL default to its existing full response. When `include_weekly_pace=false`, it SHALL calculate the same primary and secondary depletion fields, return null weekly pace, and omit account-summary, monthly-usage, trailing-demand and API-key-attribution work. The dashboard SPA SHALL request this mode after overview loads, use overview's weekly pace, and preserve the selected polling cadence.

#### Scenario: Existing projection clients retain weekly pace
- **WHEN** an authenticated client requests projections without the optional flag
- **THEN** depletion and weekly pace are returned when available

#### Scenario: Dashboard avoids duplicate weekly pace work
- **GIVEN** overview already supplies weekly pace
- **WHEN** the SPA polls projections
- **THEN** it requests `include_weekly_pace=false` and receives the same depletion values without repeating weekly pace work
