## ADDED Requirements

### Requirement: Historical recovery uses a consistent post-block time fence

Historical quota-reset recovery SHALL use whole-second precision for the post-block baseline fence. Same-second samples MUST NOT establish a recovery baseline or prevent selection of a later valid baseline. Same-second matching samples MUST still count toward window ambiguity. Existing deadline anchoring, reset confirmation, cooldown, availability, and compare-and-set checks SHALL remain in effect.

#### Scenario: Same-second sample precedes a valid weekly baseline
- **GIVEN** a Pro 200 account has a future persisted weekly block
- **AND** history contains a matching exhausted sample in the block's second followed by a matching sample in a later second
- **AND** subsequent history proves the same weekly quota reset and remains available
- **WHEN** the background scheduler refreshes and reconciles that account
- **THEN** it selects the later baseline and clears the stale block

#### Scenario: Only same-second samples match the block
- **GIVEN** only samples in the block's second match its deadline
- **WHEN** historical recovery evaluates a later quota reset
- **THEN** the persisted block remains in effect

#### Scenario: Another slot matches only in the block's second
- **GIVEN** a weekly primary reset has a valid later baseline
- **AND** another exhausted slot shares the block's deadline only in its same second
- **WHEN** historical recovery evaluates the reset
- **THEN** the ambiguous deadline keeps the account blocked
