## Why

Recovery selects the earliest quota baseline after a block using microsecond precision, but validates it using whole epoch seconds. A sample in the block's second is selected and then rejected forever, even when later matching samples prove a weekly quota reset.

## What changes

- Apply the existing whole-second post-block fence when selecting historical reset evidence.
- Skip samples in the block's second and allow later matching samples to establish the baseline.
- Preserve deadline anchoring, reset confirmation, cooldown, and compare-and-set checks.

## Impact

- Usage refresh scheduler only. No schema or configuration changes.
- Regression coverage exercises the scheduler with persisted Pro 200 weekly history.
