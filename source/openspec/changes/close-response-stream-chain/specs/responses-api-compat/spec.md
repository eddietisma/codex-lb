## ADDED Requirements

### Requirement: Response stream wrappers release their sources

Every response stream wrapper MUST close its consumed iterator when the wrapper finishes, raises, or is cancelled. Cleanup MUST propagate through the composed stream chain to service lease release. Existing error-code and native lifecycle behavior MUST remain unchanged.

#### Scenario: Native transport failure unwinds the complete chain

- **GIVEN** a service iterator holds an account stream lease
- **WHEN** a native transport failure terminates the public response wrapper
- **THEN** the underlying iterator is closed and releases its lease exactly once

#### Scenario: Downstream stops reading

- **GIVEN** a downstream reader stops while a response wrapper is suspended
- **WHEN** that wrapper is closed or cancelled
- **THEN** its consumed iterator is closed through the complete wrapper chain
