## ADDED Requirements

### Requirement: Throughput covering index

The schema SHALL include a partial request-log index on requested time restricted to successful, normal, undeleted requests with positive output tokens and positive latency. PostgreSQL SHALL include the account, model, reasoning effort, recorded plan, output tokens and latency columns. Upgrade and downgrade SHALL create and remove this index without changing request data.

#### Scenario: Existing deployment upgrades
- **WHEN** an existing database upgrades to the throughput index revision
- **THEN** the index exists and historical request rows are unchanged

#### Scenario: Index revision is reversed
- **WHEN** the throughput index revision is downgraded
- **THEN** the index is removed and historical request rows are unchanged
