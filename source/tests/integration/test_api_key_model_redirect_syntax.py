from __future__ import annotations

import json

import pytest

import app.modules.proxy.service as proxy_service
from app.core.config.settings import get_settings
from app.core.openai.model_registry import get_model_registry
from tests.integration.compact_test_helpers import _make_auth_json
from tests.integration.test_v1_models import _make_upstream_model

pytestmark = pytest.mark.integration


async def test_conditional_policy_round_trip_and_catalogs(async_client, monkeypatch):
    monkeypatch.setattr(get_settings(), "model_redirects", {})
    target = "gpt-6.1-sol"
    unchanged = "gpt-5.6-sol"
    await get_model_registry().update({"plus": [_make_upstream_model(target), _make_upstream_model(unchanged)]})
    created = await async_client.post(
        "/api/api-keys/",
        json={
            "name": "conditional catalog",
            "allowedModels": [target, unchanged],
            "applyToCodexModel": True,
            "enforcedModel": " gpt-6-sol : gpt-6.1-sol , gpt-6-luna : gpt-6.1-sol ",
        },
    )
    assert created.status_code == 200, created.text
    key = created.json()
    assert key["enforcedModel"] == "gpt-6-sol:gpt-6.1-sol,gpt-6-luna:gpt-6.1-sol"
    enabled = await async_client.put("/api/settings", json={"apiKeyAuthEnabled": True})
    assert enabled.status_code == 200
    headers = {"Authorization": f"Bearer {key['key']}"}
    for route in ("/v1/models", "/backend-api/codex/models"):
        response = await async_client.get(route, headers=headers)
        assert response.status_code == 200
        assert {target, unchanged} <= {item["id"] for item in response.json()["data"]}
        assert all(":" not in item["id"] for item in response.json()["data"])
    updated = await async_client.patch(f"/api/api-keys/{key['id']}", json={"enforcedModel": "gpt-6-sol : gpt-5.6-sol"})
    assert updated.status_code == 200, updated.text
    assert updated.json()["enforcedModel"] == "gpt-6-sol:gpt-5.6-sol"
    assert updated.json()["allowedModels"] == [target, unchanged]


@pytest.mark.parametrize("operation", ["create", "update"])
async def test_api_rejects_malformed_rules_without_replacing_policy(async_client, operation):
    original = await async_client.post("/api/api-keys/", json={"name": "original", "enforcedModel": "gpt-6.1-sol"})
    assert original.status_code == 200
    invalid = {"enforcedModel": "gpt-6-sol:gpt-6.1-sol,gpt-6-luna"}
    if operation == "create":
        response = await async_client.post("/api/api-keys/", json={"name": "invalid", **invalid})
    else:
        response = await async_client.patch(f"/api/api-keys/{original.json()['id']}", json=invalid)
    assert response.status_code == 400, response.text
    preserved = await async_client.patch(f"/api/api-keys/{original.json()['id']}", json={"name": "preserved"})
    assert preserved.status_code == 200
    assert preserved.json()["enforcedModel"] == "gpt-6.1-sol"


async def test_conditional_redirect_is_scoped_to_the_key(async_client, monkeypatch):
    monkeypatch.setattr(get_settings(), "model_redirects", {})
    auth = _make_auth_json("conditional-scope", "conditional-scope@example.invalid")
    imported = await async_client.post(
        "/api/accounts/import", files={"auth_json": ("auth.json", json.dumps(auth), "application/json")}
    )
    assert imported.status_code == 200
    enabled = await async_client.put("/api/settings", json={"apiKeyAuthEnabled": True})
    assert enabled.status_code == 200
    sent = []

    async def upstream(payload, *args, **kwargs):
        sent.append(payload.model)
        yield (
            'data: {"type":"response.completed","response":{"id":"resp_scope",'
            '"object":"response","status":"completed","output":[]}}\n\n'
        )

    monkeypatch.setattr(proxy_service, "core_stream_responses", upstream)
    for policy in ("gpt-6-luna:gpt-6.1-sol", None):
        created = await async_client.post("/api/api-keys/", json={"name": f"policy {policy}", "enforcedModel": policy})
        assert created.status_code == 200
        result = await async_client.post(
            "/backend-api/codex/responses",
            headers={"Authorization": f"Bearer {created.json()['key']}"},
            json={"model": "gpt-6-luna", "instructions": "", "input": "hello", "stream": True},
        )
        assert result.status_code == 200, result.text
        assert "response.completed" in result.text
    assert sent == ["gpt-6.1-sol", "gpt-6-luna"]
