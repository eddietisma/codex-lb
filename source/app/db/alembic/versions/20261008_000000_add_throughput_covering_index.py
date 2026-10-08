"""Add a covering partial index for dashboard throughput samples."""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20261008_000000_add_throughput_covering_index"
down_revision = "20260918_000000_merge_scim_and_overflow_heads"
branch_labels = None
depends_on = None

_INDEX = "idx_logs_throughput_covering"
_PREDICATE = (
    "deleted_at IS NULL AND status = 'success' AND request_kind = 'normal' "
    "AND output_tokens > 0 AND latency_ms > 0"
)


def upgrade() -> None:
    if op.get_bind().dialect.name == "postgresql":
        with op.get_context().autocommit_block():
            invalid = op.get_bind().execute(
                sa.text(
                    "SELECT 1 FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid "
                    "WHERE c.relname = :name AND NOT i.indisvalid"
                ),
                {"name": _INDEX},
            ).scalar()
            if invalid:
                op.execute(sa.text(f"DROP INDEX CONCURRENTLY IF EXISTS {_INDEX}"))
            op.execute(
                sa.text(
                    f"CREATE INDEX CONCURRENTLY IF NOT EXISTS {_INDEX} ON request_logs (requested_at) "
                    "INCLUDE (account_id, model, reasoning_effort, plan_type, output_tokens, latency_ms) "
                    f"WHERE {_PREDICATE}"
                )
            )
    else:
        op.create_index(_INDEX, "request_logs", ["requested_at"], sqlite_where=sa.text(_PREDICATE), if_not_exists=True)


def downgrade() -> None:
    if op.get_bind().dialect.name == "postgresql":
        with op.get_context().autocommit_block():
            op.execute(sa.text(f"DROP INDEX CONCURRENTLY IF EXISTS {_INDEX}"))
    else:
        op.drop_index(_INDEX, table_name="request_logs")
