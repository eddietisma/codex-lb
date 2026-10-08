# Avoid duplicate dashboard projections

## Why
Overview already supplies weekly pace. The SPA also polls projections and repeats account, monthly usage, attribution and weekly-pace calculations every refresh.

## What Changes
Add an optional depletion-only projections request. Keep the existing full response as the API default and have the SPA request only depletion. Preserve the selected refresh cadence and weekly pace from overview.
