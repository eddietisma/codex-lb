from __future__ import annotations

import asyncio
import json
import logging
from datetime import datetime, timezone
from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient

import app.modules.proxy.api as proxy_api
import app.modules.proxy.service as proxy_service
from app.core.crypto import TokenEncryptor
from app.core.utils.time import utcnow
from app.db.models import Account, AccountStatus
from app.db.session import SessionLocal
from app.modules.accounts.repository import AccountsRepository
from app.modules.proxy._service.websocket.mixin import _WebSocketMixin
from app.modules.proxy.load_balancer import AccountSelection
from app.modules.usage.repository import UsageRepository
from tests.integration.test_proxy_websocket_responses import (
    _completed_first_turn_upstream_batch,
    _FakeUpstreamWebSocket,
    _receive_until_terminal,
    _recovered_upstream,
    _SequencedUpstreamWebSocket,
    _websocket_settings,
    _ws_event,
)

pytestmark = pytest.mark.integration


@pytest.fixture
def quota_owner(monkeypatch):
    owner = Account(id="quota-owner", email="owner@example.invalid", plan_type="pro", status=AccountStatus.ACTIVE)
    replacement = Account(
        id="quota-replacement", email="replacement@example.invalid", plan_type="pro", status=AccountStatus.ACTIVE
    )
    state = SimpleNamespace(
        owner=owner,
        replacement=replacement,
        blocked=True,
        replacement_available=True,
        file_owner=False,
        priming=False,
        real_select=proxy_service.ProxyService._select_account_with_budget,
        selections=[],
        opened=[],
        handled=[],
        rejected=_FakeUpstreamWebSocket(
            [_ws_event({"type": "error", "error": {"code": "usage_limit_reached", "message": "Quota exhausted"}})]
        ),
        recovered=_recovered_upstream("resp_quota_recovered"),
        initial=_recovered_upstream("resp_quota_previous"),
    )

    class SettingsCache:
        async def get(self):
            return _websocket_settings()

    async def allow(*args, **kwargs):
        return None

    async def resolve_owner(*args, **kwargs):
        return owner.id

    async def resolve_file_owner(*args, **kwargs):
        return owner.id if state.file_owner else None

    async def select(self, deadline, **kwargs):
        preferred = kwargs.get("preferred_account_id")
        required = not kwargs.get("fallback_on_preferred_account_unavailable", True)
        state.selections.append((preferred, required))
        if required or not state.blocked:
            if not state.blocked:
                return AccountSelection(account=owner, error_message=None)
        elif state.replacement_available:
            return AccountSelection(account=replacement, error_message=None)
        return AccountSelection(account=None, error_code="usage_limit_reached", error_message="Owner quota exhausted")

    async def open_attempt(self, account, headers, **kwargs):
        state.opened.append(account.id)
        if state.priming:
            return account, state.initial
        return account, state.rejected if account.id == owner.id else state.recovered

    async def handle_error(self, account, error, code, **kwargs):
        state.handled.append((account.id, code))
        state.blocked = True

    monkeypatch.setattr(proxy_api, "_websocket_firewall_denial_response", allow)
    monkeypatch.setattr(proxy_api, "validate_proxy_api_key_authorization", allow)
    monkeypatch.setattr(proxy_service, "get_settings_cache", lambda: SettingsCache())
    monkeypatch.setattr(proxy_service.ProxyService, "_resolve_websocket_previous_response_owner", resolve_owner)
    monkeypatch.setattr(proxy_service.ProxyService, "_resolve_compact_turn_state_owner", resolve_owner)
    monkeypatch.setattr(proxy_service.ProxyService, "_resolve_file_account_for_responses", resolve_file_owner)
    monkeypatch.setattr(proxy_service.ProxyService, "_select_account_with_budget", select)
    monkeypatch.setattr(proxy_service.ProxyService, "_try_open_websocket_connect_attempt", open_attempt)
    monkeypatch.setattr(proxy_service.ProxyService, "_handle_stream_error", handle_error)
    monkeypatch.setattr(proxy_service.ProxyService, "_write_request_log", allow)
    return state


def _request(input_items):
    return {
        "type": "response.create",
        "model": "gpt-6.1-sol",
        "instructions": "Return OK.",
        "previous_response_id": "resp_quota_previous",
        "input": input_items,
        "stream": True,
    }


def _run(app_instance, payload, *, route="/backend-api/codex/responses", headers=None):
    with TestClient(app_instance) as client:
        with client.websocket_connect(route, headers=headers or {}) as websocket:
            websocket.send_text(json.dumps(payload))
            return _receive_until_terminal(websocket)


def _run_proxy_resend(
    app_instance,
    state,
    *,
    route="/backend-api/codex/responses",
    stage="selection",
    on_primed=None,
    extra_input=None,
    on_recovered=None,
):
    headers = {"session_id": "quota-owned-history", "thread-id": "quota-owned-thread", "user-agent": "codex/1.2"}
    history = [{"role": "user", "content": "original context"}]
    initial = _request(history)
    initial.pop("previous_response_id")
    with TestClient(app_instance) as client:
        state.priming = True
        state.blocked = False
        with client.websocket_connect(route, headers=headers) as websocket:
            websocket.send_text(json.dumps(initial))
            first_events, disconnect = _receive_until_terminal(websocket)
            assert disconnect is None
            assert first_events[-1]["type"] == "response.completed"
        state.priming = False
        state.blocked = stage == "selection"
        state.selections.clear()
        state.opened.clear()
        if on_primed is not None:
            on_primed()
        history += [
            {"role": "assistant", "content": [{"type": "output_text", "text": "OK"}]},
            {"role": "user", "content": "continue"},
        ]
        if extra_input is not None:
            history.insert(-1, extra_input)
        followup = _request(history)
        followup.pop("previous_response_id")
        with client.websocket_connect(route, headers=headers) as websocket:
            websocket.send_text(json.dumps(followup))
            result = _receive_until_terminal(websocket)
            if on_recovered is not None:
                on_recovered(websocket, history, result)
            return result, history


@pytest.mark.parametrize("route", ["/backend-api/codex/responses", "/v1/responses"])
@pytest.mark.parametrize("stage", ["selection", "upstream"])
def test_proxy_retained_full_resend_switches_exhausted_previous_response_owner(
    app_instance, quota_owner, route, stage, caplog
):
    (events, disconnect), input_items = _run_proxy_resend(app_instance, quota_owner, route=route, stage=stage)

    assert disconnect is None
    assert [event["type"] for event in events] == ["response.created", "response.completed"]
    assert quota_owner.opened[-1] == quota_owner.replacement.id
    if route == "/backend-api/codex/responses":
        assert quota_owner.selections == [(quota_owner.owner.id, True), (None, False)]
    else:
        assert quota_owner.selections == [(None, False)] * (1 if stage == "selection" else 2)
    replay = json.loads(quota_owner.recovered.sent_text[0])
    assert "previous_response_id" not in replay
    assert replay["input"] == input_items
    assert len(quota_owner.recovered.sent_text) == 1
    assert quota_owner.handled == ([] if stage == "selection" else [(quota_owner.owner.id, "usage_limit_reached")])
    records = [record for record in caplog.records if record.message.startswith("websocket_full_history_replay ")]
    if route == "/backend-api/codex/responses":
        assert len(records) == 1
        assert records[0].levelno == logging.WARNING
        diagnostic = records[0].message
        assert "stage=prepared" in diagnostic
        assert "conversation_id=sha256:" in diagnostic
        assert "session_id=sha256:" in diagnostic
        assert "previous_response_id=sha256:" in diagnostic
        assert "previous_owner=sha256:" in diagnostic
        assert "input_items=3" in diagnostic
        assert all(
            value not in diagnostic for value in ["quota-owned-thread", "quota-owned-history", "resp_quota_previous"]
        )
        assert "original context" not in diagnostic
    else:
        assert records == []


@pytest.mark.parametrize("dependency", ["delta", "file", "turn_state", "orphan_tool"])
def test_exhausted_previous_response_owner_preserves_account_owned_context(app_instance, quota_owner, dependency):
    input_items = [{"role": "user", "content": "original context"}, {"role": "user", "content": "continue"}]
    headers = {}
    if dependency == "delta":
        input_items = input_items[-1:]
    elif dependency == "file":
        quota_owner.file_owner = True
        input_items[0]["content"] = [{"type": "input_file", "file_id": "file_quota_owner"}]
    elif dependency == "turn_state":
        headers["x-codex-turn-state"] = "quota-owner-turn-state"
    else:
        input_items[-1] = {"type": "function_call_output", "call_id": "missing_call", "output": "result"}

    events, disconnect = _run(app_instance, _request(input_items), headers=headers)

    assert disconnect is None
    assert events[-1]["type"] == "error"
    assert events[-1]["error"]["code"] == "previous_response_owner_unavailable"
    assert quota_owner.opened == []
    assert quota_owner.selections == [(quota_owner.owner.id, True)]


def test_exhausted_previous_response_owner_stops_when_replacement_pool_is_empty(app_instance, quota_owner):
    quota_owner.replacement_available = False
    (events, disconnect), _ = _run_proxy_resend(app_instance, quota_owner)

    assert disconnect is None
    assert events[-1]["error"]["code"] == "usage_limit_reached"
    assert quota_owner.opened == []
    assert quota_owner.selections == [(quota_owner.owner.id, True), (None, False)]


@pytest.mark.parametrize("stage", ["selection", "upstream"])
def test_client_anchor_with_multiple_partial_messages_does_not_switch_accounts(app_instance, quota_owner, stage):
    quota_owner.blocked = stage == "selection"
    partial = [{"role": "user", "content": "later context only"}, {"role": "user", "content": "continue"}]

    events, disconnect = _run(app_instance, _request(partial))

    assert disconnect is None
    assert events[-1]["type"] in {"error", "response.failed"}
    assert quota_owner.replacement.id not in quota_owner.opened
    assert quota_owner.selections == [(quota_owner.owner.id, True)]


@pytest.mark.parametrize("item_type", ["reasoning", "compaction"])
def test_proxy_anchor_with_encrypted_context_stays_on_original_account(app_instance, quota_owner, item_type, caplog):
    (events, disconnect), _ = _run_proxy_resend(
        app_instance,
        quota_owner,
        extra_input={"type": item_type, "encrypted_content": "opaque-owner-context"},
    )

    assert disconnect is None
    assert events[-1]["type"] in {"error", "response.failed"}
    assert quota_owner.opened == []
    assert quota_owner.selections == [(quota_owner.owner.id, True)]
    assert quota_owner.recovered.sent_text == []
    assert not any(record.message.startswith("websocket_full_history_replay ") for record in caplog.records)


def test_full_history_warning_is_not_repeated_by_later_continuations(app_instance, quota_owner, monkeypatch, caplog):
    quota_owner.recovered = _SequencedUpstreamWebSocket(
        [],
        deferred_message_batches=[
            _completed_first_turn_upstream_batch("resp_quota_recovered"),
            _completed_first_turn_upstream_batch("resp_followup_one"),
            _completed_first_turn_upstream_batch("resp_followup_two"),
        ],
    )
    monkeypatch.setattr(
        proxy_service.ProxyService,
        "_resolve_websocket_previous_response_owner",
        _WebSocketMixin._resolve_websocket_previous_response_owner,
    )

    def continue_on_replacement(websocket, history, recovered):
        events, disconnect = recovered
        assert disconnect is None and events[-1]["type"] == "response.completed"
        history += [
            {"role": "assistant", "content": [{"type": "output_text", "text": "hi"}]},
            {"role": "user", "content": "next message"},
        ]
        next_request = _request(history)
        next_request.pop("previous_response_id")
        websocket.send_text(json.dumps(next_request))
        events, disconnect = _receive_until_terminal(websocket)
        assert disconnect is None and events[-1]["response"]["id"] == "resp_followup_one"
        delta = _request([{"role": "user", "content": "another iteration"}])
        delta["previous_response_id"] = "resp_followup_one"
        websocket.send_text(json.dumps(delta))
        events, disconnect = _receive_until_terminal(websocket)
        assert disconnect is None and events[-1]["response"]["id"] == "resp_followup_two"

    _run_proxy_resend(app_instance, quota_owner, on_recovered=continue_on_replacement)

    sent = [json.loads(body) for body in quota_owner.recovered.sent_text]
    assert [len(body["input"]) for body in sent] == [3, 2, 1]
    assert [body.get("previous_response_id") for body in sent] == [None, "resp_quota_recovered", "resp_followup_one"]
    assert quota_owner.opened == [quota_owner.replacement.id]
    records = [record for record in caplog.records if record.message.startswith("websocket_full_history_replay ")]
    assert len(records) == 1


@pytest.mark.asyncio
async def test_quota_owner_recovery_uses_real_account_eligibility(app_instance, quota_owner, monkeypatch):
    encryptor = TokenEncryptor()
    now = int(datetime.now(tz=timezone.utc).timestamp())
    quota_owner.owner.status = AccountStatus.RATE_LIMITED
    quota_owner.owner.reset_at = now + 604800
    quota_owner.owner.blocked_at = now
    async with SessionLocal() as session:
        accounts = AccountsRepository(session)
        usage = UsageRepository(session)
        for account in [quota_owner.owner, quota_owner.replacement]:
            account.chatgpt_account_id = account.id
            account.access_token_encrypted = encryptor.encrypt("test-access")
            account.refresh_token_encrypted = encryptor.encrypt("test-refresh")
            account.id_token_encrypted = encryptor.encrypt("test-id")
            account.last_refresh = utcnow()
            await accounts.upsert(account)
            for window, duration in [("primary", 300), ("secondary", 10080)]:
                await usage.add_entry(
                    account_id=account.id,
                    window=window,
                    used_percent=100 if account.id == quota_owner.owner.id else 20,
                    reset_at=now + duration * 60,
                    window_minutes=duration,
                )

    def restore_real_selection():
        monkeypatch.setattr(proxy_service.ProxyService, "_select_account_with_budget", quota_owner.real_select)

    (events, disconnect), input_items = await asyncio.to_thread(
        _run_proxy_resend, app_instance, quota_owner, on_primed=restore_real_selection
    )

    assert disconnect is None
    assert [event["type"] for event in events] == ["response.created", "response.completed"], events
    assert quota_owner.opened == [quota_owner.replacement.id]
    replay = json.loads(quota_owner.recovered.sent_text[0])
    assert "previous_response_id" not in replay
    assert replay["input"] == input_items
