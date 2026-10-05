from __future__ import annotations

from datetime import UTC, datetime, timedelta

import pytest

from app.core.utils.time import naive_utc_to_epoch, utcnow
from app.db.models import RequestLog
from app.db.session import SessionLocal
from tests.integration.test_dashboard_overview import _make_account

pytestmark = pytest.mark.integration


@pytest.mark.asyncio
async def test_overview_throughput_weights_rates_by_full_request_duration_model_and_plan(async_client, monkeypatch):
    now = utcnow()
    monkeypatch.setattr("app.modules.dashboard.service.utcnow", lambda: now)
    async with SessionLocal() as session:
        session.add_all(
            [
                _make_account("pro_a", "a@example.invalid", "pro"),
                _make_account("pro_b", "b@example.invalid", "pro"),
                _make_account("lite", "lite@example.invalid", "prolite"),
            ]
        )
        await session.flush()

        def sample(key, **overrides):
            values = dict(
                account_id="pro_a",
                model="gpt-6.1-sol",
                request_id=key,
                status="success",
                request_kind="normal",
                requested_at=now - timedelta(hours=1),
                output_tokens=120,
                reasoning_tokens=20,
                latency_ms=2000,
                latency_first_token_ms=1000,
            )
            return RequestLog(**(values | overrides))

        session.add_all(
            [
                sample("pro_first", reasoning_effort=" "),
                sample(
                    "pro_second",
                    account_id="pro_b",
                    output_tokens=180,
                    reasoning_tokens=0,
                    latency_ms=3500,
                    latency_first_token_ms=500,
                ),
                sample(
                    "lite_rate",
                    account_id="lite",
                    plan_type="self_serve_business_prolite",
                    output_tokens=180,
                    reasoning_tokens=None,
                    latency_ms=2000,
                    latency_first_token_ms=0,
                ),
                sample("other_model", model="gpt-6-astra"),
                sample("medium", reasoning_effort="medium"),
                sample("ultra_first", reasoning_effort="ultra", output_tokens=40, reasoning_tokens=0),
                sample("ultra_second", reasoning_effort=" ULTRA ", account_id="pro_b"),
                sample("failed", status="error"),
                sample("prewarm", request_kind="prewarm"),
                sample("warmup", request_kind="warmup"),
                sample("limit_warmup", request_kind="limit_warmup"),
                sample("missing_duration", latency_ms=None),
                sample("zero_duration", latency_ms=0),
                sample("negative_duration", latency_ms=-1),
                sample("reasoning_only", reasoning_tokens=120),
                sample("zero_tokens", output_tokens=0, reasoning_tokens=0),
                sample("negative_tokens", output_tokens=-1, reasoning_tokens=None),
                sample("missing_tokens", output_tokens=None),
                sample("deleted", deleted_at=now),
                sample("old", requested_at=now - timedelta(days=2)),
                sample("future", requested_at=now + timedelta(hours=1)),
            ]
        )
        await session.commit()
    response = await async_client.get("/api/dashboard/overview?timeframe=1d")
    assert response.status_code == 200
    bucket = (
        datetime.fromtimestamp(naive_utc_to_epoch(now - timedelta(hours=1)) // 3600 * 3600, UTC)
        .isoformat()
        .replace("+00:00", "Z")
    )
    expected = [
        {
            "model": "gpt-6-astra",
            "reasoningEffort": None,
            "planType": "pro",
            "averageTokensPerSecond": 60.0,
            "sampleCount": 1,
        },
        {
            "model": "gpt-6.1-sol",
            "reasoningEffort": None,
            "planType": "pro",
            "averageTokensPerSecond": 56.0,
            "sampleCount": 3,
        },
        {
            "model": "gpt-6.1-sol",
            "reasoningEffort": None,
            "planType": "prolite",
            "averageTokensPerSecond": 90.0,
            "sampleCount": 1,
        },
        {
            "model": "gpt-6.1-sol",
            "reasoningEffort": "medium",
            "planType": "pro",
            "averageTokensPerSecond": 60.0,
            "sampleCount": 1,
        },
        {
            "model": "gpt-6.1-sol",
            "reasoningEffort": "ultra",
            "planType": "pro",
            "averageTokensPerSecond": 40.0,
            "sampleCount": 2,
        },
    ]
    assert response.json()["throughput"] == [{"bucketStart": bucket, **row} for row in expected]


@pytest.mark.asyncio
async def test_overview_throughput_does_not_multiply_parallel_chat_speeds(async_client, monkeypatch):
    now = utcnow()
    monkeypatch.setattr("app.modules.dashboard.service.utcnow", lambda: now)
    single_start = now - timedelta(hours=2)
    parallel_start = now - timedelta(hours=1)
    async with SessionLocal() as session:
        session.add_all([_make_account(f"pro_{i}", f"pro_{i}@example.invalid", "pro") for i in range(3)])
        await session.flush()
        for i, (account, started_at, generated_tokens, elapsed_ms) in enumerate(
            [
                (0, single_start, 100, 4000),
                (0, parallel_start, 100, 4000),
                (1, parallel_start, 200, 8000),
                (2, parallel_start, 300, 12000),
            ]
        ):
            session.add(
                RequestLog(
                    account_id=f"pro_{account}",
                    model="gpt-6.1-sol",
                    reasoning_effort="medium",
                    request_id=f"chat_{i}",
                    status="success",
                    request_kind="normal",
                    requested_at=started_at,
                    output_tokens=generated_tokens,
                    reasoning_tokens=20,
                    latency_ms=elapsed_ms,
                    latency_first_token_ms=1000,
                )
            )
        await session.commit()
    response = await async_client.get("/api/dashboard/overview?timeframe=1d")
    assert response.status_code == 200
    rows = response.json()["throughput"]
    assert len(rows) == 2
    assert [row["sampleCount"] for row in rows] == [1, 3]
    assert [row["averageTokensPerSecond"] for row in rows] == [25.0, 25.0]


@pytest.mark.asyncio
async def test_overview_throughput_includes_reasoning_without_first_token_timing(async_client, monkeypatch):
    now = utcnow()
    monkeypatch.setattr("app.modules.dashboard.service.utcnow", lambda: now)
    async with SessionLocal() as session:
        session.add(_make_account("pro", "pro@example.invalid", "pro"))
        await session.flush()
        for i, first_token_ms in enumerate([9990, None]):
            session.add(
                RequestLog(
                    account_id="pro",
                    model="gpt-6.1-sol",
                    reasoning_effort="max",
                    request_id=f"thinking_{i}",
                    status="success",
                    request_kind="normal",
                    requested_at=now - timedelta(hours=1),
                    output_tokens=600,
                    reasoning_tokens=500,
                    latency_ms=10000,
                    latency_first_token_ms=first_token_ms,
                    latency_queue_ms=20000,
                )
            )
        await session.commit()
    response = await async_client.get("/api/dashboard/overview?timeframe=1d")
    assert response.status_code == 200
    rows = response.json()["throughput"]
    assert len(rows) == 1
    assert rows[0]["sampleCount"] == 2
    assert rows[0]["averageTokensPerSecond"] == 60.0


@pytest.mark.asyncio
async def test_overview_throughput_respects_timeframe_and_recorded_plan(async_client, monkeypatch):
    now = utcnow()
    monkeypatch.setattr("app.modules.dashboard.service.utcnow", lambda: now)
    async with SessionLocal() as session:
        session.add(_make_account("account", "account@example.invalid", "pro"))
        await session.flush()
        session.add_all(
            [
                RequestLog(
                    account_id="account",
                    model="gpt-6.1-sol",
                    request_id="recent",
                    status="success",
                    requested_at=now - timedelta(hours=1),
                    output_tokens=100,
                    latency_ms=2000,
                    latency_first_token_ms=1000,
                    plan_type="prolite",
                ),
                RequestLog(
                    account_id="account",
                    model="gpt-6.1-sol",
                    request_id="older",
                    status="success",
                    requested_at=now - timedelta(days=2),
                    output_tokens=300,
                    latency_ms=2000,
                    latency_first_token_ms=1000,
                    plan_type="prolite",
                ),
            ]
        )
        await session.commit()
    daily = (await async_client.get("/api/dashboard/overview?timeframe=1d")).json()["throughput"]
    weekly = (await async_client.get("/api/dashboard/overview?timeframe=7d")).json()["throughput"]

    def bucket_at(value, seconds):
        return (
            datetime.fromtimestamp(naive_utc_to_epoch(value) // seconds * seconds, UTC)
            .isoformat()
            .replace("+00:00", "Z")
        )

    common = {"model": "gpt-6.1-sol", "reasoningEffort": None, "planType": "prolite", "sampleCount": 1}
    assert daily == [
        {**common, "bucketStart": bucket_at(now - timedelta(hours=1), 3600), "averageTokensPerSecond": 50.0}
    ]
    assert weekly == [
        {**common, "bucketStart": bucket_at(now - timedelta(days=2), 21600), "averageTokensPerSecond": 150.0},
        {**common, "bucketStart": bucket_at(now - timedelta(hours=1), 21600), "averageTokensPerSecond": 50.0},
    ]
