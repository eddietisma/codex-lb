## ADDED Requirements

### Requirement: Hard continuity owners remain selectable during transient backoff

Selection MUST admit the sole resolved hard continuity owner through transient error-backoff fallback when that owner otherwise passes eligibility checks. It MUST preserve the owner's error counters. Persisted unavailability, quota exhaustion, and cooldowns MUST retain their existing behavior. Ordinary multi-account selection MUST continue preferring eligible healthy accounts.

#### Scenario: Active owner in transient backoff

- **WHEN** an anchored request narrows selection to an otherwise eligible active owner in transient backoff
- **THEN** selection admits that owner without clearing its error counters

#### Scenario: Persistently unavailable owner

- **WHEN** a required owner is paused or otherwise fails persisted eligibility
- **THEN** selection fails closed without selecting a sibling
