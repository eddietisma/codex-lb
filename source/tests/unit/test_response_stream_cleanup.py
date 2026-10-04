from __future__ import annotations

import asyncio
from collections.abc import AsyncIterator
from contextlib import nullcontext
from typing import Any, cast
from unittest.mock import AsyncMock

import pytest
from cryptography.fernet import Fernet

from app.core.clients.proxy import ProxyResponseError
from app.core.crypto import TokenEncryptor
from app.core.utils.sse import format_sse_event
from app.modules.proxy import api
from app.modules.proxy.load_balancer import AccountConcurrencyCaps, LoadBalancer


@pytest.mark.asyncio
@pytest.mark.parametrize("outcome", ["success", "transport_failure", "downstream_close", "cancellation"])
async def test_response_stream_wrappers_release_account_lease(outcome: str, monkeypatch: pytest.MonkeyPatch) -> None:
    balancer = LoadBalancer(cast(Any, lambda: nullcontext()), encryptor=TokenEncryptor(key=Fernet.generate_key()))
    caps = AccountConcurrencyCaps(response_create_limit=1, stream_limit=1)
    lease = await balancer.acquire_account_lease(
        "account-stream-cleanup", kind="stream", estimated_tokens=1024, concurrency_caps=caps
    )
    assert lease is not None
    assert await balancer.account_pressure_snapshot(lease.account_id) == (0, 1, 1024)
    release = AsyncMock(wraps=balancer.release_account_lease)
    monkeypatch.setattr(balancer, "release_account_lease", release)
    waiting = asyncio.Event()

    async def service_stream() -> AsyncIterator[str]:
        try:
            yield format_sse_event(
                {"type": "response.created", "response": {"id": "resp_cleanup", "status": "in_progress"}}
            )
            if outcome == "transport_failure":
                yield format_sse_event(
                    {
                        "type": "response.failed",
                        "response": {
                            "id": "resp_cleanup",
                            "status": "failed",
                            "error": {"code": "stream_incomplete", "message": "Synthetic transport failure."},
                        },
                        api.SYNTHETIC_TRANSPORT_FAILURE_MARKER: True,
                    }
                )
            elif outcome == "success":
                yield format_sse_event(
                    {"type": "response.completed", "response": {"id": "resp_cleanup", "status": "completed"}}
                )
                return
            waiting.set()
            await asyncio.Event().wait()
        finally:
            await balancer.release_account_lease(lease)

    errors = api._stream_response_error_events(
        service_stream(), owns_reservation=False, reservation=None, preserve_native_failure_lifecycle=True
    )
    public = api._normalize_public_responses_stream(
        errors, enforce_openai_sdk_contract=False, preserve_native_failure_lifecycle=True
    )
    await anext(public)
    if outcome == "transport_failure":
        with pytest.raises(ProxyResponseError) as error:
            await anext(public)
        assert error.value.payload["error"]["code"] == "stream_incomplete"
    elif outcome == "success":
        remaining = [block async for block in public]
        assert any("response.completed" in block for block in remaining)
    elif outcome == "cancellation":
        read = asyncio.ensure_future(anext(public))
        await asyncio.wait_for(waiting.wait(), timeout=1)
        read.cancel()
        with pytest.raises(asyncio.CancelledError):
            await read
    await api._close_responses_stream_best_effort(public, action="composed wrapper regression")
    release.assert_awaited_once_with(lease)
    assert await balancer.account_pressure_snapshot(lease.account_id) == (0, 0, 0)

    replacement = await balancer.acquire_account_lease(lease.account_id, kind="stream", concurrency_caps=caps)
    assert replacement is not None
    await balancer.release_account_lease(replacement)
