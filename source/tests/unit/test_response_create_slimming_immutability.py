from copy import deepcopy
from typing import Callable
from unittest.mock import Mock

import pytest

import app.core.clients.proxy as core_proxy
import app.modules.proxy._service.response_create as response_create
import app.modules.proxy._service.streaming.helpers as streaming_helpers
from app.core.types import JsonValue

Slimmer = Callable[..., tuple[dict[str, JsonValue], dict[str, int] | None]]


@pytest.mark.parametrize(
    "slimmer",
    [
        pytest.param(core_proxy._slim_response_create_payload_for_upstream, id="core"),
        pytest.param(response_create._slim_response_create_payload_for_upstream, id="response-create"),
        pytest.param(streaming_helpers._slim_response_create_payload_for_upstream, id="streaming"),
    ],
)
def test_slimming_preserves_shared_source_history_and_recent_turn(slimmer: Slimmer) -> None:
    text_part: dict[str, JsonValue] = {"type": "input_text", "text": "keep", "extra": {"values": [1, 2]}}
    image_part: dict[str, JsonValue] = {"type": "input_image", "image_url": "data:image/png;base64,AA"}
    content: list[JsonValue] = [text_part, image_part]
    historical: dict[str, JsonValue] = {"role": "user", "content": content}
    tool: dict[str, JsonValue] = {
        "type": "function_call_output",
        "call_id": "tool",
        "output": content,
        "content": content,
    }
    recent: dict[str, JsonValue] = {"role": "user", "content": content}
    payload: dict[str, JsonValue] = {"input": [historical, tool, recent], "metadata": {"key": ["value"]}}
    original = deepcopy(payload)

    slimmed, summary = slimmer(payload, max_bytes=256)

    notice = core_proxy._response_create_inline_image_notice_part()
    assert slimmed == {
        **original,
        "input": [
            {"role": "user", "content": [text_part, notice]},
            {
                "type": "function_call_output",
                "call_id": "tool",
                "output": [text_part, notice],
                "content": [text_part, notice],
            },
            recent,
        ],
    }
    assert summary == {"historical_tool_outputs_slimmed": 0, "historical_images_slimmed": 3}
    assert payload == original
    assert slimmed["input"] is not payload["input"]

    # Reusing the same source objects across fields and turns must not rewrite any alias.
    again, again_summary = slimmer(slimmed, max_bytes=256)
    assert again is slimmed
    assert again_summary is None
    assert payload == original


@pytest.mark.parametrize(
    "slimmer",
    [
        core_proxy._slim_response_create_payload_for_upstream,
        response_create._slim_response_create_payload_for_upstream,
        streaming_helpers._slim_response_create_payload_for_upstream,
    ],
)
def test_slimming_replaces_output_and_content_without_mutating_item(slimmer: Slimmer) -> None:
    tool: dict[str, JsonValue] = {
        "type": "apply_patch_call_output",
        "call_id": "patch",
        "status": "completed",
        "output": "x" * (32 * 1024 + 1),
        "content": {"type": "image_url", "image_url": {"url": "data:image/png;base64,AA"}},
    }
    payload: dict[str, JsonValue] = {"input": [tool, {"role": "user", "content": "latest"}]}
    original = deepcopy(payload)

    slimmed, summary = slimmer(payload, max_bytes=256)

    assert payload == original
    assert summary == {"historical_tool_outputs_slimmed": 1, "historical_images_slimmed": 1}
    slimmed_input = slimmed["input"]
    assert isinstance(slimmed_input, list)
    slimmed_tool = slimmed_input[0]
    assert isinstance(slimmed_tool, dict)
    assert slimmed_tool == {
        **tool,
        "output": core_proxy._RESPONSE_CREATE_TOOL_OUTPUT_OMISSION_NOTICE.format(bytes=32 * 1024 + 1),
        "content": core_proxy._response_create_inline_image_notice_part(),
    }


@pytest.mark.asyncio
async def test_image_inlining_after_slimming_does_not_mutate_borrowed_content(monkeypatch: pytest.MonkeyPatch) -> None:
    external: dict[str, JsonValue] = {"type": "input_image", "image_url": "https://example.com/image.png"}
    payload: dict[str, JsonValue] = {
        "input": [
            {"role": "user", "content": [external, {"type": "input_image", "image_url": "data:image/png;base64,AA"}]},
            {"role": "user", "content": [external]},
        ]
    }
    original = deepcopy(payload)
    slimmed, _ = core_proxy._slim_response_create_payload_for_upstream(payload, max_bytes=256)
    slimmed_before = deepcopy(slimmed)

    async def fetch(*args: object) -> str:
        return "data:image/png;base64,BB"

    monkeypatch.setattr(core_proxy, "_fetch_image_data_url", fetch)
    inlined = await core_proxy._inline_input_image_urls(slimmed, Mock(), 1.0)

    assert payload == original
    assert slimmed == slimmed_before
    assert inlined != slimmed
