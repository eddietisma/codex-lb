from __future__ import annotations

import pytest
from pydantic import ValidationError

from app.core.config.settings import Settings

pytestmark = pytest.mark.unit


def test_model_redirects_default_empty(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("CODEX_LB_MODEL_REDIRECTS", raising=False)
    assert Settings(_env_file=None).model_redirects == {}


def test_model_redirects_parse_environment(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("CODEX_LB_MODEL_REDIRECTS", '{"gpt-6-sol":"gpt-6.1-sol"}')
    assert Settings(_env_file=None).model_redirects == {"gpt-6-sol": "gpt-6.1-sol"}


@pytest.mark.parametrize("value", [None, "", "  ", "{}", {}])
def test_model_redirects_empty_values(value) -> None:
    assert Settings(_env_file=None, model_redirects=value).model_redirects == {}


@pytest.mark.parametrize(
    "value",
    [
        "not-json",
        "[]",
        "null",
        '{"gpt-6-sol": 123}',
        {"": "target"},
        {"source": "  "},
        {1: "target"},
        {"source": None},
        {"source": "target", "target": "other"},
        {"source": "target", "target": "source"},
        {"source": "source"},
    ],
)
def test_model_redirects_reject_invalid_configuration(value) -> None:
    with pytest.raises(ValidationError):
        Settings(_env_file=None, model_redirects=value)
