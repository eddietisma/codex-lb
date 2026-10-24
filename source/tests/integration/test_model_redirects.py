from __future__ import annotations

import json
from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient

import app.modules.proxy.api as proxy_api
import app.modules.proxy.service as proxy_service
from app.core.config.settings import get_settings
from app.core.openai.models import CompactResponsePayload
from app.db.session import SessionLocal
from app.modules.api_keys.repository import ApiKeysRepository
from app.modules.api_keys.service import ApiKeyCreateData, ApiKeysService
from tests.integration.compact_test_helpers import _make_auth_json
from tests.integration.test_http_responses_bridge import _FakeBridgeUpstreamWebSocket, _install_bridge_settings
from tests.integration.test_proxy_websocket_responses import (
    _FakeUpstreamWebSocket,
    _websocket_response_batch,
)

pytestmark = pytest.mark.integration

_REDIRECTS = dict.fromkeys(("gpt-6-astra", "gpt-6-sol", "gpt-6-luna"), "gpt-6.1-sol")
_MODELS = [*_REDIRECTS, "gpt-6.1-sol", "gpt-5.6-sol"]


@pytest.fixture(params=["deployment", "api_key"])
def configured_redirects(monkeypatch, request):
    monkeypatch.setattr(get_settings(), "model_redirects", _REDIRECTS if request.param == "deployment" else {})
    return (
        ",".join(f"{source}:{target}" for source, target in _REDIRECTS.items()) if request.param == "api_key" else None
    )


@pytest.fixture
async def redirect_key(async_client, configured_redirects):
    auth = _make_auth_json("redirect-account", "redirect@example.invalid")
    imported = await async_client.post(
        "/api/accounts/import", files={"auth_json": ("auth.json", json.dumps(auth), "application/json")}
    )
    assert imported.status_code == 200
    enabled = await async_client.put("/api/settings", json={"apiKeyAuthEnabled": True})
    assert enabled.status_code == 200
    created = await async_client.post(
        "/api/api-keys/",
        json={
            "name": "redirect",
            "allowedModels": ["gpt-6.1-sol", "gpt-5.6-sol"],
            "enforcedModel": configured_redirects,
        },
    )
    assert created.status_code == 200
    return created.json()["key"]


@pytest.mark.parametrize("requested_model", _MODELS)
@pytest.mark.parametrize("route", ["/backend-api/codex/responses", "/v1/responses", "/v1/chat/completions"])
async def test_http_redirects_before_authorization_and_upstream(
    async_client, monkeypatch, redirect_key, requested_model, route
):
    sent = []

    async def upstream(payload, *args, **kwargs):
        sent.append(payload.to_payload())
        yield (
            'data: {"type":"response.completed","response":{"id":"resp_redirect",'
            '"object":"response","status":"completed","output":[]}}\n\n'
        )

    monkeypatch.setattr(proxy_service, "core_stream_responses", upstream)
    body = {"model": requested_model, "stream": True, "reasoning": {"effort": "high"}}
    if route.endswith("chat/completions"):
        body.pop("reasoning")
        body.update(messages=[{"role": "user", "content": "Reply OK"}], reasoning_effort="high")
    else:
        body.update(instructions="", input="Reply OK")
    result = await async_client.post(route, headers={"Authorization": f"Bearer {redirect_key}"}, json=body)
    assert result.status_code == 200, result.text
    assert len(sent) == 1, result.text
    assert sent[0]["model"] == _REDIRECTS.get(requested_model, requested_model)
    assert sent[0]["reasoning"]["effort"] == "high"


@pytest.mark.parametrize("requested_model", _MODELS)
@pytest.mark.parametrize("route", ["/backend-api/codex/responses/compact", "/v1/responses/compact"])
async def test_compact_redirects_match_normal_requests(async_client, monkeypatch, redirect_key, requested_model, route):
    sent = []

    async def upstream(payload, *args, **kwargs):
        sent.append(payload.to_payload())
        return CompactResponsePayload.model_validate(
            {
                "object": "response.compaction",
                "compaction_summary": {"id": "cmp_redirect", "encrypted_content": "summary"},
            }
        )

    monkeypatch.setattr(proxy_service, "core_compact_responses", upstream)
    result = await async_client.post(
        route,
        headers={"Authorization": f"Bearer {redirect_key}"},
        json={"model": requested_model, "instructions": "", "input": []},
    )
    assert result.status_code == 200, result.text
    assert len(sent) == 1
    assert sent[0]["model"] == _REDIRECTS.get(requested_model, requested_model)


@pytest.mark.parametrize("requested_model", list(_REDIRECTS))
async def test_http_bridge_redirects_reach_upstream_frame(async_client, monkeypatch, redirect_key, requested_model):
    _install_bridge_settings(monkeypatch, enabled=True)
    upstream = _FakeBridgeUpstreamWebSocket()

    async def fresh(self, account, **kwargs):
        return account

    async def connect(*args, **kwargs):
        return upstream

    monkeypatch.setattr(proxy_service.ProxyService, "_ensure_fresh_with_budget", fresh)
    monkeypatch.setattr(proxy_service, "connect_responses_websocket", connect)
    result = await async_client.post(
        "/backend-api/codex/responses",
        headers={"Authorization": f"Bearer {redirect_key}"},
        json={"model": requested_model, "instructions": "Reply OK", "input": "hello", "stream": True},
    )
    assert result.status_code == 200, result.text
    assert "response.completed" in result.text
    assert json.loads(upstream.sent_text[0])["model"] == "gpt-6.1-sol"


@pytest.mark.parametrize("requested_model", _MODELS)
@pytest.mark.parametrize("route", ["/backend-api/codex/responses", "/v1/responses"])
def test_websocket_redirects_reach_upstream_frame(
    app_instance, monkeypatch, configured_redirects, requested_model, route
):
    upstream = _FakeUpstreamWebSocket(_websocket_response_batch("resp_redirect"))
    selected_models = []

    async def create_key():
        async with SessionLocal() as session:
            service = ApiKeysService(ApiKeysRepository(session))
            key = await service.create_key(
                ApiKeyCreateData(
                    name="websocket redirect",
                    allowed_models=["gpt-6.1-sol", "gpt-5.6-sol"],
                    enforced_model=configured_redirects,
                )
            )
            return await service.get_key_by_id(key.id)

    async def connect(self, headers, **kwargs):
        selected_models.append(kwargs["model"])
        return SimpleNamespace(id="redirect-account"), upstream

    monkeypatch.setattr(proxy_service.ProxyService, "_connect_proxy_websocket", connect)
    with TestClient(app_instance) as client:
        api_key = client.portal.call(create_key)

        async def authorize(_authorization, *, request=None):
            return api_key

        monkeypatch.setattr(proxy_api, "validate_proxy_api_key_authorization", authorize)
        with client.websocket_connect(route) as websocket:
            websocket.send_text(json.dumps({"type": "response.create", "model": requested_model, "input": "Reply OK"}))
            events = [json.loads(websocket.receive_text()) for _ in range(2)]
    assert [event["type"] for event in events] == ["response.created", "response.completed"]
    expected_model = _REDIRECTS.get(requested_model, requested_model)
    assert selected_models == [expected_model]
    assert json.loads(upstream.sent_text[0])["model"] == expected_model
