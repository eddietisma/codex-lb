from __future__ import annotations

import asyncio
import json
import uuid
from types import SimpleNamespace

import pytest

import app.modules.proxy.api as proxy_api
from app.db.models import StickySession, StickySessionKind
from app.db.session import SessionLocal
from app.dependencies import get_proxy_service_for_app
from app.modules.proxy import service as proxy_service
from app.modules.proxy.affinity import _codex_session_selection_key
from tests.integration.test_http_responses_bridge import (
    _FakeBridgeUpstreamWebSocket,
    _import_account,
    _install_bridge_settings,
)


@pytest.mark.asyncio
@pytest.mark.parametrize(
    ("route", "stream"),
    [("/backend-api/codex/responses", True), ("/v1/responses", True), ("/v1/responses", False)],
)
async def test_model_transition_followup_reuses_durable_child(
    async_client, app_instance, monkeypatch, route, stream
) -> None:
    _install_bridge_settings(monkeypatch, enabled=True)
    parent_id = await _import_account(async_client, "transition_parent", "parent@example.invalid")
    service = get_proxy_service_for_app(app_instance)
    connections: list[_FakeBridgeUpstreamWebSocket] = []

    async def fresh(self, account, **kwargs):
        return account

    async def connect(*args, **kwargs):
        upstream = _FakeBridgeUpstreamWebSocket(response_id_prefix=f"resp_transition_{len(connections)}")
        connections.append(upstream)
        return upstream

    monkeypatch.setattr(proxy_service.ProxyService, "_ensure_fresh_with_budget", fresh)
    monkeypatch.setattr(proxy_service, "connect_responses_websocket", connect)
    session_id = str(uuid.uuid4())
    history = [
        {"role": "user", "content": "initial task"},
        {"role": "assistant", "content": "initial answer"},
        {"role": "user", "content": "continue"},
    ]
    body = {"model": "gpt-5.1", "instructions": "Return OK.", "input": history, "stream": stream}
    first = await async_client.post(route, headers={"session_id": session_id}, json=body)
    assert first.status_code == 200, first.text
    parent_turn_state = first.headers["x-codex-turn-state"]
    parent = await service._durable_bridge.lookup_turn_state_target(turn_state=parent_turn_state, api_key_id=None)
    assert parent is not None and parent.account_id == parent_id
    assert (
        await service.prepare_http_bridge_turn_state(
            {"x-codex-turn-state": parent_turn_state}, model="gpt-5.1", api_key=None
        )
        == parent_turn_state
    )
    assert (
        await service.prepare_http_bridge_turn_state(
            {"x-codex-turn-state": "unknown-token"}, model="gpt-5.4", api_key=None
        )
        == "unknown-token"
    )
    assert (
        await service.prepare_http_bridge_turn_state(
            {"x-codex-turn-state": parent_turn_state}, model="gpt-5.4", api_key=SimpleNamespace(id="foreign-key")
        )
        == parent_turn_state
    )
    child_id = await _import_account(async_client, "transition_child", "child@example.invalid")
    async with SessionLocal() as db:
        for key in (parent_turn_state, _codex_session_selection_key(parent_turn_state)):
            await db.merge(StickySession(key=key, kind=StickySessionKind.CODEX_SESSION, account_id=child_id))
        await db.commit()
    new_history = [*history, {"role": "assistant", "content": "OK"}, {"role": "user", "content": "switch model"}]
    changed = await async_client.post(
        route,
        headers={"session_id": session_id, "x-codex-turn-state": parent_turn_state},
        json={**body, "model": "gpt-5.4", "input": new_history},
    )
    assert changed.status_code == 200, changed.text
    assert "response.failed" not in changed.text, changed.text
    child_turn_state = changed.headers["x-codex-turn-state"]
    child = await service._durable_bridge.lookup_turn_state_target(turn_state=child_turn_state, api_key_id=None)
    before_followup = len(connections)
    followup = await async_client.post(
        route,
        headers={"session_id": session_id, "x-codex-turn-state": child_turn_state},
        json={
            **body,
            "model": "gpt-5.4",
            "input": [*new_history, {"role": "assistant", "content": "OK"}, {"role": "user", "content": "next turn"}],
        },
    )
    assert followup.status_code == 200 and "response.failed" not in followup.text, followup.text
    assert len(connections) == before_followup
    assert child is not None and child.account_id == child_id
    assert child.model == "gpt-5.4"
    assert child_turn_state != parent_turn_state
    unchanged_parent = await service._durable_bridge.lookup_turn_state_target(
        turn_state=parent_turn_state, api_key_id=None
    )
    assert unchanged_parent is not None and unchanged_parent.session_id == parent.session_id
    assert unchanged_parent.account_id == parent_id and unchanged_parent.model == "gpt-5.1"
    latest = json.loads(connections[-1].sent_text[-1])
    assert latest.get("previous_response_id") is not None


@pytest.mark.asyncio
@pytest.mark.parametrize("stream", [True, False])
@pytest.mark.parametrize("failure_type", [RuntimeError, asyncio.CancelledError])
async def test_turn_state_lookup_failure_releases_reservation(async_client, monkeypatch, stream, failure_type) -> None:
    _install_bridge_settings(monkeypatch, enabled=True)
    await _import_account(async_client, "lookup_failure", "lookup-failure@example.invalid")
    reservation = object()
    releases = []
    failure = failure_type("turn-state lookup failed")

    async def reserve(*args, **kwargs):
        return reservation

    async def prepare(*args, **kwargs):
        raise failure

    async def release(value):
        releases.append(value)

    monkeypatch.setattr(proxy_api, "_enforce_request_limits", reserve)
    monkeypatch.setattr(proxy_api, "_release_reservation", release)
    monkeypatch.setattr(proxy_service.ProxyService, "prepare_http_bridge_turn_state", prepare)
    with pytest.raises(failure_type):
        await async_client.post(
            "/v1/responses",
            json={"model": "gpt-5.4", "instructions": "Return OK.", "input": "continue", "stream": stream},
        )
    assert releases == [reservation]
