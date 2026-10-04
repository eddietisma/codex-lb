from __future__ import annotations

import pytest

from app.modules.proxy.replay_safety import responses_payload_is_account_neutral_fresh_replay

pytestmark = pytest.mark.unit


@pytest.mark.parametrize("generate", [True, False, None, 0, 1, "false", [], {}])
def test_generate_control_is_replay_safe_only_when_boolean(generate):
    payload = {"model": "gpt-6.1-sol", "input": "self-contained", "generate": generate}
    assert responses_payload_is_account_neutral_fresh_replay(payload) is isinstance(generate, bool)


@pytest.mark.parametrize(
    "owner_state",
    [
        {"previous_response_id": "resp_owner"},
        {"conversation": "conv_owner"},
        {"input": [{"type": "input_file", "file_id": "file_owner"}]},
        {"tools": [{"type": "file_search", "vector_store_ids": ["vs_owner"]}]},
        {"unknown_field": True},
    ],
)
def test_generate_control_does_not_release_ownership(owner_state):
    payload = {"model": "gpt-6.1-sol", "input": "self-contained", "generate": False, **owner_state}
    assert not responses_payload_is_account_neutral_fresh_replay(payload)
