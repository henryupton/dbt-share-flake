import pytest

from macro_harness import (
    ALL_SHARE_PRIVILEGES,
    StubContext,
    build_package,
    make_node,
)


@pytest.fixture
def ctx():
    """A fresh stub dbt context. Arrange it before acting; the package reads it live."""
    return StubContext()


@pytest.fixture
def pkg(ctx):
    """The package's macros, callable as pkg.macro_name(...)."""
    return build_package(ctx)


@pytest.fixture
def drifted_share(ctx):
    """One share that exists and has drifted from configuration.

    Configuration wants analytics.public.orders shared; Snowflake also still has a stale
    grant on analytics.public.legacy. So a clean full run should produce three grants and
    one revoke.
    """
    ctx.nodes = [make_node("model.p.orders", "orders", {"shares": ["partner_share"]})]
    ctx.vars["snowflake_shares"] = {"partner_share": {}}
    ctx.on_query(r"SHOW SHARES", [{"name": "MYORG.ACCT.PARTNER_SHARE", "kind": "OUTBOUND"}])
    ctx.on_query(r"SHOW GRANTS TO SHARE", [
        {"privilege": "SELECT", "granted_on": "TABLE", "name": "ANALYTICS.PUBLIC.LEGACY"},
    ])
    ctx.grant_role_privileges(ALL_SHARE_PRIVILEGES)
    return ctx
