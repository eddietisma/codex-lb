## Why

The dashboard needs a readable comparison of throughput trends over time for each model, reasoning effort and account type.

## What changes

Add a time-series line chart with timestamp tooltips and a model/reasoning selector. Return per-bucket average generation rates and sample counts in the overview response, combining accounts of the same plan type. Match the dashboard palette and loading layout.

## Impact

Dashboard API and frontend. No persistence or configuration changes.
