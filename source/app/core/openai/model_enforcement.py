"""Parse the API key's unconditional model or exact model redirect rules."""

from dataclasses import dataclass
from typing import overload


@dataclass(frozen=True)
class ModelEnforcement:
    target: str | None = None
    redirects: tuple[tuple[str, str], ...] = ()


def parse_model_enforcement(value: str | None) -> ModelEnforcement:
    if value is None or not value.strip():
        return ModelEnforcement()
    value = value.strip()
    if ":" not in value and "," not in value:
        return ModelEnforcement(target=value)
    redirects: dict[str, str] = {}
    for rule in value.split(","):
        parts = rule.split(":")
        if len(parts) != 2 or not all(part.strip() for part in parts):
            raise ValueError("enforced_model redirects must use source:target pairs with non-empty models")
        source, target = (part.strip() for part in parts)
        if source in redirects:
            raise ValueError("enforced_model redirects must not repeat a source model")
        redirects[source] = target
    if set(redirects).intersection(redirects.values()):
        raise ValueError("enforced_model redirects must not contain chains or cycles")
    return ModelEnforcement(redirects=tuple(redirects.items()))


@overload
def resolve_enforced_model(value: str | None, requested_model: str) -> str: ...


@overload
def resolve_enforced_model(value: str | None, requested_model: str | None) -> str | None: ...


def resolve_enforced_model(value: str | None, requested_model: str | None) -> str | None:
    policy = parse_model_enforcement(value)
    if policy.target is not None:
        return policy.target
    return next((target for source, target in policy.redirects if source == requested_model), requested_model)


def unconditional_enforced_model(value: str | None) -> str | None:
    return parse_model_enforcement(value).target


def normalize_model_enforcement(value: str | None) -> str | None:
    policy = parse_model_enforcement(value)
    return policy.target or (",".join(f"{source}:{target}" for source, target in policy.redirects) or None)
