"""End-to-end wiring of the on-run-end hook.

The entrypoint's output is spliced into the hook's SQL, so it must render to an empty
string. A macro that returns `none` puts a literal "None" into the statement dbt runs.
"""
from types import SimpleNamespace

from macro_harness import ALL_SHARE_PRIVILEGES, make_node


def configure_both(ctx):
    ctx.nodes = [
        make_node("model.p.feed", "feed", {"listings": ["my_listing"], "shares": ["direct_share"]}),
    ]
    ctx.vars["snowflake_listings"] = {"my_listing": {"title": "T", "description": "D"}}
    ctx.vars["snowflake_shares"] = {"direct_share": {"accounts": ["ABC12345"]}}
    ctx.on_query(r"SHOW SHARES", [])
    ctx.on_query(r"SHOW LISTINGS", [])
    ctx.grant_role_privileges(ALL_SHARE_PRIVILEGES)
    return ctx


class TestEntrypoint:
    def test_renders_to_an_empty_string(self, ctx, pkg):
        configure_both(ctx)
        assert pkg.entrypoint() == ""

    def test_grants_to_both_the_direct_and_the_listing_share(self, ctx, pkg):
        configure_both(ctx)
        pkg.entrypoint()
        assert "TO SHARE direct_share" in ctx.sql
        assert "TO SHARE my_listing_share" in ctx.sql

    def test_creates_the_listing_before_granting_to_its_share(self, ctx, pkg):
        configure_both(ctx)
        pkg.entrypoint()
        assert ctx.sql.index("CREATE ORGANIZATION LISTING") < ctx.sql.index("TO SHARE my_listing_share")

    def test_touches_nothing_on_a_blocked_target(self, ctx, pkg):
        configure_both(ctx)
        ctx.vars["snowflake_sharing_targets"] = ["prod"]
        ctx.target = SimpleNamespace(name="dev")
        pkg.entrypoint()
        assert ctx.executed_sql == []

    def test_touches_nothing_when_disabled(self, ctx, pkg):
        configure_both(ctx)
        ctx.vars["snowflake_sharing_enabled"] = False
        pkg.entrypoint()
        assert ctx.executed_sql == []

    def test_announces_a_dry_run(self, ctx, pkg):
        configure_both(ctx)
        ctx.vars["snowflake_sharing_dry_run"] = True
        pkg.entrypoint()
        assert ctx.ddl == []
        assert "no changes will be made" in ctx.log_text

    def test_works_with_shares_only(self, ctx, pkg):
        ctx.nodes = [make_node("model.p.o", "o", {"shares": ["direct_share"]})]
        ctx.vars["snowflake_shares"] = {"direct_share": {}}
        ctx.on_query(r"SHOW SHARES", [])
        ctx.grant_role_privileges(ALL_SHARE_PRIVILEGES)
        pkg.entrypoint()
        assert "TO SHARE direct_share" in ctx.sql

    def test_works_with_listings_only(self, ctx, pkg):
        ctx.nodes = [make_node("model.p.o", "o", {"listings": ["my_listing"]})]
        ctx.vars["snowflake_listings"] = {"my_listing": {"title": "T", "description": "D"}}
        ctx.on_query(r"SHOW SHARES", [])
        ctx.on_query(r"SHOW LISTINGS", [])
        ctx.grant_role_privileges(ALL_SHARE_PRIVILEGES)
        pkg.entrypoint()
        assert "TO SHARE my_listing_share" in ctx.sql

    def test_says_so_when_nothing_is_configured(self, ctx, pkg):
        pkg.entrypoint()
        assert ctx.executed_sql == []
        assert "no shares or listings configured" in ctx.log_text


class TestNewShareConfiguration:
    """A share the package creates must receive its accounts, or it is unusable. This is
    deliberately not gated behind snowflake_shares_alter_share, which governs later
    changes only."""

    def _new_share(self, ctx):
        ctx.nodes = [make_node("model.p.orders", "orders", {"shares": ["partner_share"]})]
        ctx.on_query(r"SHOW SHARES", [])
        ctx.grant_role_privileges(ALL_SHARE_PRIVILEGES)
        return ctx

    def test_new_share_receives_its_accounts(self, ctx, pkg):
        self._new_share(ctx)
        pkg.process_shares({"partner_share": {"accounts": ["ABC12345"]}})
        assert "CREATE SHARE IF NOT EXISTS partner_share" in ctx.sql
        assert "ADD ACCOUNTS = ABC12345" in ctx.sql

    def test_accounts_are_added_after_the_grants(self, ctx, pkg):
        # A share with no objects in it cannot have accounts added.
        self._new_share(ctx)
        pkg.process_shares({"partner_share": {"accounts": ["ABC12345"]}})
        assert ctx.sql.index("GRANT USAGE ON DATABASE") < ctx.sql.index("ADD ACCOUNTS")

    def test_existing_share_is_left_alone_by_default(self, ctx, pkg):
        ctx.nodes = [make_node("model.p.orders", "orders", {"shares": ["partner_share"]})]
        ctx.on_query(r"SHOW SHARES", [{"name": "A.B.PARTNER_SHARE", "kind": "OUTBOUND"}])
        ctx.on_query(r"SHOW GRANTS TO SHARE", [
            {"privilege": "USAGE", "granted_on": "DATABASE", "name": "ANALYTICS"},
            {"privilege": "USAGE", "granted_on": "SCHEMA", "name": "ANALYTICS.PUBLIC"},
            {"privilege": "SELECT", "granted_on": "TABLE", "name": "ANALYTICS.PUBLIC.ORDERS"},
        ])
        ctx.grant_role_privileges(ALL_SHARE_PRIVILEGES)

        pkg.process_shares({"partner_share": {"accounts": ["ABC12345"]}})

        assert ctx.statements_matching(r"ALTER SHARE") == []
        assert ctx.statements_matching(r"DESCRIBE SHARE") == []

    def test_alter_share_reconciles_an_existing_share(self, ctx, pkg):
        # The existing consumer set comes from the `to` column of SHOW SHARES.
        ctx.nodes = [make_node("model.p.orders", "orders", {"shares": ["partner_share"]})]
        ctx.vars["snowflake_shares_alter_share"] = True
        ctx.on_query(r"SHOW SHARES", [
            {"name": "A.B.PARTNER_SHARE", "kind": "OUTBOUND", "to": "OLD_ACCT"},
        ])
        ctx.on_query(r"SHOW GRANTS TO SHARE", [])
        ctx.grant_role_privileges(ALL_SHARE_PRIVILEGES)

        pkg.process_shares({"partner_share": {"accounts": ["ABC12345"]}})

        assert "ADD ACCOUNTS = ABC12345" in ctx.sql
        assert "REMOVE ACCOUNTS = OLD_ACCT" in ctx.sql

    def test_alter_share_is_a_noop_when_the_consumer_is_already_attached(self, ctx, pkg):
        # Previously the existing set always read as empty, so every run re-issued
        # ADD ACCOUNTS for accounts that were already on the share.
        ctx.nodes = [make_node("model.p.orders", "orders", {"shares": ["partner_share"]})]
        ctx.vars["snowflake_shares_alter_share"] = True
        ctx.on_query(r"SHOW SHARES", [
            {"name": "A.B.PARTNER_SHARE", "kind": "OUTBOUND", "to": "ABC12345"},
        ])
        ctx.on_query(r"SHOW GRANTS TO SHARE", [
            {"privilege": "USAGE", "granted_on": "DATABASE", "name": "ANALYTICS"},
            {"privilege": "USAGE", "granted_on": "SCHEMA", "name": "ANALYTICS.PUBLIC"},
            {"privilege": "SELECT", "granted_on": "TABLE", "name": "ANALYTICS.PUBLIC.ORDERS"},
        ])
        ctx.grant_role_privileges(ALL_SHARE_PRIVILEGES)

        pkg.process_shares({"partner_share": {"accounts": ["ABC12345"]}})

        assert ctx.statements_matching(r"ALTER SHARE") == []
