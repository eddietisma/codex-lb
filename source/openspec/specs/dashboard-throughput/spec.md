# Dashboard throughput

## Purpose
Compare request-duration-weighted average generation speed, including reasoning tokens and thinking time, by model, reasoning effort and account plan type.

## Requirements

### Requirement: Bucketed throughput averages

The overview MUST group throughput by UTC time bucket, model, recorded reasoning effort and canonical account plan type. Each point MUST include its UTC bucket start, sample count and request-duration-weighted average of per-request generation rates. The rate MUST be `sum(output_tokens) * 1000 / sum(latency_ms)`. Reported output tokens already include reasoning tokens; reasoning tokens MUST NOT be subtracted or added again. The denominator MUST include each eligible request's full recorded duration, including thinking and time to first visible output. Overlapping request durations MUST be counted separately. The denominator MUST NOT subtract first-token latency, use elapsed bucket time or multiply the rate by concurrent chat count.

#### Scenario: Requests are weighted by full request duration

- **GIVEN** two eligible requests in one bucket and model/effort/type group generate 120 total output tokens in two seconds and 180 total output tokens in 3.5 seconds, including thinking
- **WHEN** the overview is requested
- **THEN** that point has an average of 54.55 tok/s and a sample count of two

#### Scenario: Parallel chats do not multiply model speed

- **GIVEN** three overlapping eligible requests in one group each generate 25 total output tokens per second over their full request durations
- **WHEN** the overview is requested
- **THEN** that point reports 25 tok/s and a sample count of three

### Requirement: Eligible throughput samples

Samples MUST be successful normal requests within the selected window, not deleted, with positive reported output tokens and positive full request duration. Reasoning-only output MUST contribute. First-token timing and a reasoning-token breakdown MUST NOT be required. Failed requests, internal traffic, missing or nonpositive output tokens, and missing or nonpositive full request duration MUST NOT contribute.

#### Scenario: Prewarm and unusable timing are excluded

- **GIVEN** a bucket contains normal requests, prewarms and requests without full request duration
- **WHEN** throughput is calculated
- **THEN** only eligible normal requests contribute

#### Scenario: Thinking and buffered output are included

- **GIVEN** two successful normal requests each generate 600 total output tokens, including 500 reasoning tokens, in ten seconds, with one first visible event at 9.99 seconds and the other missing first-token timing
- **WHEN** throughput is calculated
- **THEN** both requests contribute and the point reports 60 tok/s with a sample count of two

#### Scenario: Reasoning-only generations are counted

- **GIVEN** a successful normal request reports 200 output tokens, all of them reasoning, in four seconds
- **WHEN** throughput is calculated
- **THEN** the request contributes 50 tok/s

### Requirement: Recorded grouping identities

The request-time plan type MUST take precedence over the current account type. Missing values MAY use the current type; missing both MUST form an unknown group. Plan aliases MUST be canonicalized. Reasoning effort MUST be trimmed and lowercased; missing or blank values MUST form a not-recorded group without inferring model defaults.

#### Scenario: Historic plans and efforts are retained

- **GIVEN** an account changed plan after a request and the request records medium effort
- **WHEN** that request is charted
- **THEN** it contributes to its recorded plan and medium group

### Requirement: Time-series comparison chart

The dashboard MUST plot average generated tokens per second over time, with a model/reasoning selector and one line per account type. Its description MUST state that reasoning tokens and thinking time are included and each point represents a time-bucket average. It MUST follow the overview time range and refresh behavior and use the shared dashboard graph palette. The pro label MUST be Pro 200 and prolite MUST be Business Premium. Individual account identities MUST NOT be exposed.

#### Scenario: Account types are compared for one model and effort

- **GIVEN** Pro 200 and Business Premium requests exist for medium and ultra effort
- **WHEN** medium is selected
- **THEN** the chart shows the medium time series for both account types

### Requirement: Missing samples and loading states

Missing buckets MUST appear as gaps, not zero throughput, and lines MUST NOT connect across them. Empty datasets MUST show an empty state. Full-overview and lazy-chart loading MUST show a matching skeleton that reserves the card's position and plot height.

#### Scenario: A missing time bucket is a gap

- **GIVEN** an account type has samples before and after an empty bucket
- **WHEN** its line is rendered
- **THEN** the line breaks at that bucket

### Requirement: Timestamp tooltips

Hovering MUST show a thin theme-aware vertical guide and a tooltip containing the timestamp, account-type rates and sample counts. It MUST NOT show a filled cursor overlay or replace series colors with white highlights. Hover dots MUST follow the existing report chart style, with a four-pixel radius, a 1.5-pixel outline and the popover theme color in the center.

#### Scenario: Hover compares samples at one time

- **GIVEN** both account types have samples at a timestamp
- **WHEN** the pointer is over that time
- **THEN** the tooltip displays both values and counts beside a thin guide, with outlined hover dots using the popover theme color in the center
