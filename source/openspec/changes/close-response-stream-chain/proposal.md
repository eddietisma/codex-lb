# Close the response stream chain

## Why

Native transport failures and downstream cancellation can leave nested response iterators suspended, preventing service-level lease release.

## What changes

Close consumed iterators in the existing public, reasoning and error stream wrappers using the existing cleanup helper. Preserve current error codes and native failure behavior.
