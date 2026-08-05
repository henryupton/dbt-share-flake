"""Existence checks against Snowflake's SHOW ... LIKE wildcards.

Snowflake treats '_' as a single-character wildcard in a LIKE pattern, and every share
name in practice contains one. Trusting the pattern therefore over-matches: 'test_share_1'
also matches 'testXshareY1'. A false positive means the object is silently never created,
so the pattern is only used to narrow and the match is made exactly afterwards.
"""
import pytest

from macro_harness import CompilerError


class TestShareExists:
    def test_false_when_like_over_matches(self, ctx, pkg):
        ctx.on_query(r"SHOW SHARES", [{"name": "MYORG.ACCT.TESTXSHAREY1", "kind": "OUTBOUND"}])
        assert pkg.share_exists("test_share_1") is False

    def test_true_on_exact_match_among_over_matches(self, ctx, pkg):
        ctx.on_query(r"SHOW SHARES", [
            {"name": "MYORG.ACCT.TESTXSHAREY1", "kind": "OUTBOUND"},
            {"name": "MYORG.ACCT.TEST_SHARE_1", "kind": "OUTBOUND"},
        ])
        assert pkg.share_exists("test_share_1") is True

    def test_matches_through_account_qualification(self, ctx, pkg):
        ctx.on_query(r"SHOW SHARES", [{"name": "MYORG.MYACCT.PARTNER_SHARE", "kind": "OUTBOUND"}])
        assert pkg.share_exists("partner_share") is True

    def test_ignores_inbound_shares(self, ctx, pkg):
        # A share imported from another account is not something we can grant on.
        ctx.on_query(r"SHOW SHARES", [{"name": "PROVIDER.ACCT.TEST_SHARE_1", "kind": "INBOUND"}])
        assert pkg.share_exists("test_share_1") is False

    def test_false_when_nothing_returned(self, ctx, pkg):
        ctx.on_query(r"SHOW SHARES", [])
        assert pkg.share_exists("partner_share") is False

    def test_copes_with_a_missing_kind_column(self, ctx, pkg):
        ctx.on_query(r"SHOW SHARES", [{"name": "PARTNER_SHARE"}])
        assert pkg.share_exists("partner_share") is True

    def test_validates_the_name_before_querying(self, ctx, pkg):
        with pytest.raises(CompilerError):
            pkg.share_exists("x'; DROP SHARE y; --")
        assert ctx.executed_sql == []


class TestListingExists:
    def test_false_when_like_over_matches(self, ctx, pkg):
        ctx.on_query(r"SHOW LISTINGS", [{"name": "TESTXLISTINGY1"}])
        assert pkg.listing_exists("test_listing_1") is False

    def test_true_on_exact_match(self, ctx, pkg):
        ctx.on_query(r"SHOW LISTINGS", [{"name": "TEST_LISTING_1"}])
        assert pkg.listing_exists("test_listing_1") is True

    def test_false_when_nothing_returned(self, ctx, pkg):
        ctx.on_query(r"SHOW LISTINGS", [])
        assert pkg.listing_exists("my_listing") is False

    def test_validates_the_name_before_querying(self, ctx, pkg):
        with pytest.raises(CompilerError):
            pkg.listing_exists("x; DROP SHARE y")
        assert ctx.executed_sql == []
