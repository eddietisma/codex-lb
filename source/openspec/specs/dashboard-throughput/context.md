The chart compares observed generation rate for a selected model and recorded reasoning effort, with one line per account plan type. It includes all reported output tokens, including reasoning, and uses a request-duration-weighted average across eligible requests. Reported output tokens already contain reasoning tokens, so the calculation does not subtract them or add them again.

Each point divides total generated tokens by the sum of each request's full duration. For example, 120 tokens in two seconds and 180 tokens in 3.5 seconds produce 300 / 5.5 = 54.55 tok/s. Three concurrent requests each generating 25 tokens per second of their own duration still show 25 tok/s because overlapping durations are counted separately.

Subtracting time to first visible output hides much of a reasoning model's thinking time and makes buffered tool output appear artificially fast. A request generating 600 output tokens, including 500 reasoning tokens, in ten seconds has an observed generation rate of 60 tok/s, even if its first visible event arrives at 9.99 seconds. Counting only the 100 non-reasoning tokens would measure output delivery instead of total generation. Full request duration also permits successful requests with missing first-token timing to contribute.

Duration is the persisted latency_ms, including thinking, initial processing and output delivery. Separately recorded pre-attempt queue time is not added. The chart measures observed generation rate across recorded requests rather than a benchmark of internal token decoding throughput.

The 1d view covers the last 24 hours with hourly points; it does not show one average for the whole day. The 7d view uses six-hour points and the 30d view uses daily points.
