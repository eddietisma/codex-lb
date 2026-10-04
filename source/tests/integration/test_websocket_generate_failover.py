from __future__ import annotations

import json

import pytest
from fastapi.testclient import TestClient

import app.modules.proxy.api as proxy_api
import app.modules.proxy.service as proxy_service
from app.db.models import Account, AccountStatus
from app.modules.proxy.load_balancer import AccountSelection
from tests.integration.test_proxy_websocket_responses import (
    _FakeUpstreamWebSocket,
    _receive_until_terminal,
    _recovered_upstream,
    _websocket_settings,
    _ws_event,
)

pytestmark = pytest.mark.integration


@pytest.mark.parametrize("route", ["/backend-api/codex/responses", "/v1/responses"])
@pytest.mark.parametrize("generate", [False, True])
def test_generate_request_fails_over_after_precreated_quota_rejection(app_instance, monkeypatch, route, generate):
    accounts = [
        Account(
            id=f"generate_account_{i}",
            email=f"generate-{i}@example.invalid",
            plan_type="pro",
            status=AccountStatus.ACTIVE,
        )
        for i in range(2)
    ]
    blocked = set()
    selected = []
    opened = []
    first = _FakeUpstreamWebSocket(
        [_ws_event({"type": "error", "error": {"code": "usage_limit_reached", "message": "usage limit reached"}})]
    )
    second = _recovered_upstream("resp_generate_recovered")

    class SettingsCache:
        async def get(self):
            return _websocket_settings()

    async def allow(*args, **kwargs):
        return None

    async def select(self, deadline, **kwargs):
        preferred = kwargs.get("preferred_account_id")
        required = not kwargs.get("fallback_on_preferred_account_unavailable", True)
        candidates = [a for a in accounts if a.id not in blocked and (not required or a.id == preferred)]
        if not candidates:
            return AccountSelection(account=None, error_message="No available accounts")
        account = candidates[0]
        selected.append(account.id)
        return AccountSelection(account=account, error_message=None)

    async def open_attempt(self, account, headers, **kwargs):
        opened.append(account.id)
        return account, first if account.id == accounts[0].id else second

    async def handle_error(self, account, error, code, **kwargs):
        assert code == "usage_limit_reached"
        blocked.add(account.id)

    monkeypatch.setattr(proxy_api, "_websocket_firewall_denial_response", allow)
    monkeypatch.setattr(proxy_api, "validate_proxy_api_key_authorization", allow)
    monkeypatch.setattr(proxy_service, "get_settings_cache", lambda: SettingsCache())
    monkeypatch.setattr(proxy_service.ProxyService, "_select_account_with_budget", select)
    monkeypatch.setattr(proxy_service.ProxyService, "_try_open_websocket_connect_attempt", open_attempt)
    monkeypatch.setattr(proxy_service.ProxyService, "_handle_stream_error", handle_error)
    monkeypatch.setattr(proxy_service.ProxyService, "_write_request_log", allow)
    payload = {
        "type": "response.create",
        "model": "gpt-6.1-sol",
        "instructions": "Return OK.",
        "input": [{"role": "user", "content": "self-contained request"}],
        "generate": generate,
        "stream": True,
    }
    with TestClient(app_instance) as client:
        with client.websocket_connect(route) as websocket:
            websocket.send_text(json.dumps(payload))
            events, disconnect = _receive_until_terminal(websocket)
    assert disconnect is None
    assert events[-1]["type"] == "response.completed", events
    assert selected == opened == [accounts[0].id, accounts[1].id]
    assert len(first.sent_text) == len(second.sent_text) == 1
    assert json.loads(second.sent_text[0])["generate"] is generate
