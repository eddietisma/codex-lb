import pytest

from app.core.openai.model_enforcement import (
    parse_model_enforcement,
    resolve_enforced_model,
    unconditional_enforced_model,
)


@pytest.mark.parametrize("value", ["a:", ":b", "a:b,", "a:b,c", "a:b,a:c", "a:b,b:c", "a:a", "a:b,b:a"])
def test_invalid_redirects(value: str) -> None:
    with pytest.raises(ValueError, match="enforced_model"):
        parse_model_enforcement(value)


def test_redirects_trim_separators_and_match_exactly() -> None:
    policy = " gpt-6-sol : gpt-6.1-sol , gpt-6-astra:gpt-6.1-sol "
    assert resolve_enforced_model(policy, "gpt-6-sol") == "gpt-6.1-sol"
    assert resolve_enforced_model(policy, "gpt-6-astra") == "gpt-6.1-sol"
    assert resolve_enforced_model(policy, "gpt-6-sol-extra") == "gpt-6-sol-extra"
    assert resolve_enforced_model(policy, "gpt-reserve") == "gpt-reserve"
    assert resolve_enforced_model(policy, None) is None
    assert unconditional_enforced_model(policy) is None


def test_bare_model_remains_unconditional() -> None:
    assert resolve_enforced_model(" target ", "anything") == "target"
    assert resolve_enforced_model("target", None) == "target"
    assert unconditional_enforced_model("target") == "target"
    assert resolve_enforced_model(None, "anything") == "anything"
