from __future__ import annotations

import time
from datetime import datetime, timezone

import pytest

from app.core.crypto import TokenEncryptor
from app.core.usage import refresh_scheduler as scheduler_module
from app.core.usage.models import RateLimitPayload, UsagePayload, UsageWindow
from app.core.utils.time import utcnow
from app.db.models import Account, AccountStatus
from app.db.session import SessionLocal
from app.modules.accounts.repository import AccountsRepository
from app.modules.usage import updater as updater_module
from app.modules.usage.repository import UsageRepository

pytestmark = [pytest.mark.integration, pytest.mark.usage_refresh_request_path]


@pytest.mark.asyncio
@pytest.mark.parametrize(
    ("baseline_offset", "deadline_offset", "ambiguous", "recovers"),
    [(1.5, 0, False, True), (0.75, 0, False, False), (1.5, 60, False, False), (1.5, 0, True, False)],
    ids=["later-baseline", "same-second-only", "unrelated-deadline", "same-second-ambiguous-slot"],
)
async def test_scheduler_weekly_reset_baseline_precision(
    db_setup,
    monkeypatch: pytest.MonkeyPatch,
    baseline_offset: float,
    deadline_offset: int,
    ambiguous: bool,
    recovers: bool,
) -> None:
    del db_setup
    now = int(time.time())
    blocked_at = now - 3600
    blocked_until = now + 3 * 24 * 3600
    encryptor = TokenEncryptor()
    account = Account(
        id="weekly-baseline-precision",
        chatgpt_account_id="weekly-workspace",
        email="weekly@example.com",
        plan_type="prolite",
        access_token_encrypted=encryptor.encrypt("access"),
        refresh_token_encrypted=encryptor.encrypt("refresh"),
        id_token_encrypted=encryptor.encrypt("id"),
        last_refresh=utcnow(),
        status=AccountStatus.RATE_LIMITED,
        blocked_at=blocked_at,
        reset_at=blocked_until,
        limit_warmup_enabled=False,
    )
    async with SessionLocal() as session:
        await AccountsRepository(session).upsert(account)
        usage = UsageRepository(session)
        # The first matching row was written during the 429's whole second.
        # Later exhausted samples and an early weekly reset survive a restart.
        for observed_at, used, reset_at in (
            (blocked_at + 0.5, 100.0, blocked_until + deadline_offset),
            (blocked_at + baseline_offset, 100.0, blocked_until + deadline_offset),
            (now - 180, 100.0, blocked_until + 60),
            (now - 120, 0.0, now - 120 + 604_800),
            (now - 90, 0.0, now - 90 + 604_800),
        ):
            await usage.add_entry(
                account.id,
                used,
                window="primary",
                recorded_at=datetime.fromtimestamp(observed_at, timezone.utc).replace(tzinfo=None),
                reset_at=reset_at,
                window_minutes=10_080,
            )
        if ambiguous:
            await usage.add_entry(
                account.id,
                100.0,
                window="secondary",
                recorded_at=datetime.fromtimestamp(blocked_at + 0.5, timezone.utc).replace(tzinfo=None),
                reset_at=blocked_until,
                window_minutes=10_080,
            )

    async def fetch_usage(**_kwargs) -> UsagePayload:
        return UsagePayload(
            plan_type="prolite",
            rate_limit=RateLimitPayload(
                primary_window=UsageWindow(
                    used_percent=0.0,
                    reset_at=now + 604_800,
                    limit_window_seconds=604_800,
                ),
            ),
        )

    monkeypatch.setattr(updater_module, "fetch_usage", fetch_usage)
    scheduler = scheduler_module.UsageRefreshScheduler(interval_seconds=60, enabled=True)
    await scheduler._refresh_as_leader()

    async with SessionLocal() as session:
        persisted = await AccountsRepository(session).get_by_id(account.id)
        latest = await UsageRepository(session).latest_entry_for_account(account.id, window="primary")
    assert persisted is not None and latest is not None
    assert latest.recorded_at > datetime.fromtimestamp(now - 90, timezone.utc).replace(tzinfo=None)
    assert latest.used_percent == 0.0
    assert (persisted.status, persisted.reset_at, persisted.blocked_at) == (
        (AccountStatus.ACTIVE, None, None) if recovers else (AccountStatus.RATE_LIMITED, blocked_until, blocked_at)
    )
