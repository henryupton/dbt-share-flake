"""Account diffing and ALTER SHARE generation.

Snowflake only accepts SHARE_RESTRICTIONS as a modifier on ADD ACCOUNTS, not as a
settable property of an existing share, so there is no such thing as changing it on its
own. See https://docs.snowflake.com/en/sql-reference/sql/alter-share
"""
import pytest

from macro_harness import CompilerError


class TestDiffShareConfiguration:
    def test_detects_additions_and_removals(self, pkg):
        diff = pkg.diff_share_configuration(
            {"accounts": ["NEW_ACCT", "KEEP"]},
            {"accounts": ["KEEP", "OLD_ACCT"]},
        )
        assert diff["accounts_to_add"] == ["NEW_ACCT"]
        assert diff["accounts_to_remove"] == ["OLD_ACCT"]

    def test_ignores_case_when_matching(self, pkg):
        # Snowflake reports accounts upper-cased regardless of how they were configured.
        diff = pkg.diff_share_configuration(
            {"accounts": ["abc12345"]},
            {"accounts": ["ABC12345"]},
        )
        assert diff["accounts_to_add"] == [] and diff["accounts_to_remove"] == []

    def test_detects_a_restriction_change(self, pkg):
        diff = pkg.diff_share_configuration(
            {"accounts": [], "share_restrictions": True},
            {"accounts": [], "share_restrictions": False},
        )
        assert diff["restrictions_changed"] is True
        assert diff["share_restrictions"] is True

    def test_defaults_restrictions_to_false(self, pkg):
        diff = pkg.diff_share_configuration({"accounts": []}, {"accounts": []})
        assert diff["share_restrictions"] is False
        assert diff["restrictions_changed"] is False

    def test_treats_unknown_existing_restrictions_as_unchanged(self, pkg):
        # get_share_configuration reports None for an existing share, because Snowflake
        # does not expose the property. Calling that a change would warn on every run
        # about something no run can resolve.
        diff = pkg.diff_share_configuration(
            {"accounts": ["A1"], "share_restrictions": True},
            {"accounts": ["A1"], "share_restrictions": None},
        )
        assert diff["restrictions_changed"] is False

    def test_removal_is_detected_against_a_real_existing_set(self, pkg):
        # The regression this guards: existing accounts used to read as empty always, so
        # dropping an account from configuration produced no removal at all.
        diff = pkg.diff_share_configuration(
            {"accounts": []},
            {"accounts": ["IEDKCNV.UNWRAP_US_EAST_CRITICAL"]},
        )
        assert diff["accounts_to_remove"] == ["IEDKCNV.UNWRAP_US_EAST_CRITICAL"]

    def test_treats_missing_keys_as_empty(self, pkg):
        diff = pkg.diff_share_configuration({}, {})
        assert diff["accounts_to_add"] == [] and diff["accounts_to_remove"] == []

    def test_validates_configured_accounts(self, pkg):
        with pytest.raises(CompilerError):
            pkg.diff_share_configuration({"accounts": ["a, b REMOVE ACCOUNTS = c"]}, {"accounts": []})


class TestUpdateShareConfiguration:
    def test_add_accounts_carries_share_restrictions(self, ctx, pkg):
        pkg.update_share_configuration(
            "partner_share",
            {"accounts": ["ABC12345"], "share_restrictions": True},
            {"accounts": []},
        )
        assert ctx.statements_matching(
            r"ALTER SHARE partner_share ADD ACCOUNTS = ABC12345 SHARE_RESTRICTIONS = TRUE")

    def test_never_emits_a_standalone_set_share_restrictions(self, ctx, pkg):
        pkg.update_share_configuration(
            "partner_share",
            {"accounts": ["ABC12345"], "share_restrictions": False},
            {"accounts": []},
        )
        assert "SET SHARE_RESTRICTIONS" not in ctx.sql

    def test_adds_multiple_accounts_in_one_statement(self, ctx, pkg):
        pkg.update_share_configuration("s", {"accounts": ["A1", "B2"]}, {"accounts": []})
        assert len(ctx.statements_matching(r"ADD ACCOUNTS")) == 1
        assert "ADD ACCOUNTS = A1, B2" in ctx.sql

    def test_removes_accounts_no_longer_configured(self, ctx, pkg):
        pkg.update_share_configuration("s", {"accounts": []}, {"accounts": ["GONE"]})
        assert "REMOVE ACCOUNTS = GONE" in ctx.sql

    def test_restriction_only_change_warns_instead_of_emitting_ddl(self, ctx, pkg):
        pkg.update_share_configuration(
            "s",
            {"accounts": [], "share_restrictions": True},
            {"accounts": [], "share_restrictions": False},
        )
        assert ctx.executed_sql == []
        assert any("only accepts SHARE_RESTRICTIONS" in w for w in ctx.warnings)

    def test_does_nothing_when_already_in_sync(self, ctx, pkg):
        pkg.update_share_configuration("s", {"accounts": ["A1"]}, {"accounts": ["A1"]})
        assert ctx.executed_sql == []
        assert ctx.warnings == []

    def test_dry_run_logs_without_executing(self, ctx, pkg):
        pkg.update_share_configuration(
            "s", {"accounts": ["A1"]}, {"accounts": []}, dry_run=True)
        assert ctx.executed_sql == []
        assert "[dry run]" in ctx.log_text

    def test_accepts_a_precomputed_diff(self, ctx, pkg):
        diff = pkg.diff_share_configuration({"accounts": ["A1"]}, {"accounts": []})
        pkg.update_share_configuration("s", {}, {}, config_diff=diff)
        assert "ADD ACCOUNTS = A1" in ctx.sql

    def test_validates_the_share_name(self, ctx, pkg):
        with pytest.raises(CompilerError):
            pkg.update_share_configuration("x; DROP SHARE y", {"accounts": []}, {"accounts": []})
        assert ctx.executed_sql == []


class TestGetShareConfiguration:
    """Accounts come from SHOW SHARES.

    DESCRIBE SHARE lists the objects inside an outbound share, never its consumers, so
    reading accounts from it always yielded an empty set — which re-added attached
    accounts every run and made removal undetectable.
    """

    def test_reads_accounts_from_the_to_column(self, ctx, pkg):
        ctx.on_query(r"SHOW SHARES", [
            {"kind": "OUTBOUND", "name": "PARTNER_SHARE",
             "to": "ABC12345,XYZ99999"},
        ])
        config = pkg.get_share_configuration("partner_share")
        assert config["accounts"] == ["ABC12345", "XYZ99999"]

    def test_does_not_read_describe_share(self, ctx, pkg):
        ctx.on_query(r"SHOW SHARES", [
            {"kind": "OUTBOUND", "name": "PARTNER_SHARE", "to": "ABC12345"},
        ])
        pkg.get_share_configuration("partner_share")
        assert "DESCRIBE SHARE" not in ctx.sql

    def test_handles_a_single_account(self, ctx, pkg):
        ctx.on_query(r"SHOW SHARES", [
            {"kind": "OUTBOUND", "name": "PARTNER_SHARE",
             "to": "IEDKCNV.UNWRAP_US_EAST_CRITICAL"},
        ])
        config = pkg.get_share_configuration("partner_share")
        assert config["accounts"] == ["IEDKCNV.UNWRAP_US_EAST_CRITICAL"]

    def test_treats_no_consumers_as_empty(self, ctx, pkg):
        ctx.on_query(r"SHOW SHARES", [
            {"kind": "OUTBOUND", "name": "PARTNER_SHARE", "to": ""},
        ])
        assert pkg.get_share_configuration("partner_share")["accounts"] == []

    def test_matches_an_account_qualified_name(self, ctx, pkg):
        # SHOW SHARES may report an outbound share account-qualified, as share_exists
        # already allows for.
        ctx.on_query(r"SHOW SHARES", [
            {"kind": "OUTBOUND", "name": "MYORG.MYACCT.PARTNER_SHARE", "to": "ABC12345"},
        ])
        assert pkg.get_share_configuration("partner_share")["accounts"] == ["ABC12345"]

    def test_ignores_a_share_the_like_pattern_caught_by_wildcard(self, ctx, pkg):
        # `_` is a single-character wildcard in LIKE, so a share name containing an
        # underscore can match a sibling. Only the exact name may contribute accounts.
        ctx.on_query(r"SHOW SHARES", [
            {"kind": "OUTBOUND", "name": "PARTNERXSHARE", "to": "WRONG1"},
            {"kind": "OUTBOUND", "name": "PARTNER_SHARE", "to": "RIGHT1"},
        ])
        assert pkg.get_share_configuration("partner_share")["accounts"] == ["RIGHT1"]

    def test_ignores_an_inbound_share_of_the_same_name(self, ctx, pkg):
        ctx.on_query(r"SHOW SHARES", [
            {"kind": "INBOUND", "name": "PARTNER_SHARE", "to": ""},
            {"kind": "OUTBOUND", "name": "PARTNER_SHARE", "to": "ABC12345"},
        ])
        assert pkg.get_share_configuration("partner_share")["accounts"] == ["ABC12345"]

    def test_defaults_when_the_share_is_absent(self, ctx, pkg):
        ctx.on_query(r"SHOW SHARES", [])
        config = pkg.get_share_configuration("partner_share")
        assert config == {"accounts": [], "share_restrictions": None}

    def test_reports_share_restrictions_as_unknown(self, ctx, pkg):
        # Snowflake exposes it in neither SHOW SHARES nor DESCRIBE SHARE.
        ctx.on_query(r"SHOW SHARES", [
            {"kind": "OUTBOUND", "name": "PARTNER_SHARE", "to": "ABC12345"},
        ])
        assert pkg.get_share_configuration("partner_share")["share_restrictions"] is None

    def test_validates_the_share_name(self, ctx, pkg):
        with pytest.raises(CompilerError):
            pkg.get_share_configuration("x'; DROP SHARE y; --")
        assert ctx.executed_sql == []


class TestGrantAndRevokeSql:
    def test_grant_sql_shape(self, pkg):
        sql = pkg.get_grant_sql("analytics.public.orders", "partner_share", "SELECT", "TABLE")
        assert "GRANT SELECT ON TABLE analytics.public.orders TO SHARE partner_share" in sql

    def test_revoke_sql_shape(self, pkg):
        sql = pkg.get_revoke_sql("analytics.public.orders", "partner_share", "SELECT", "TABLE")
        assert "REVOKE SELECT ON TABLE analytics.public.orders FROM SHARE partner_share" in sql

    def test_normalises_table_variants(self, pkg):
        sql = pkg.get_grant_sql("a.b.c", "s", "SELECT", "DYNAMIC TABLE")
        assert "ON TABLE a.b.c" in sql

    def test_preserves_views(self, pkg):
        assert "ON VIEW a.b.c" in pkg.get_grant_sql("a.b.c", "s", "SELECT", "VIEW")

    @pytest.mark.parametrize("builder", ["get_grant_sql", "get_revoke_sql"])
    def test_validates_the_share_name(self, pkg, builder):
        with pytest.raises(CompilerError):
            getattr(pkg, builder)("a.b.c", "s; DROP SHARE x", "SELECT", "TABLE")

    def test_create_share_is_idempotent(self, pkg):
        assert "CREATE SHARE IF NOT EXISTS partner_share" in pkg.get_create_share_sql("partner_share")
