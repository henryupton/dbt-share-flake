"""Grant key normalisation.

The key is how a desired grant is matched against an existing one. Desired object names
come from dbt's relation rendering, which honours the project's quoting config; existing
ones come from SHOW GRANTS TO SHARE, which always reports them unquoted and upper-cased.
If those two do not normalise to the same key, every grant looks simultaneously missing
and stale and the package churns forever.
"""
from macro_harness import ALL_SHARE_PRIVILEGES, make_node


class TestMakeGrantKey:
    def test_joins_parts_with_a_pipe(self, pkg):
        assert pkg.make_grant_key("analytics", "USAGE", "DATABASE") == "analytics|usage|database"

    def test_is_case_insensitive(self, pkg):
        assert pkg.make_grant_key("ANALYTICS.PUBLIC.ORDERS", "SELECT", "TABLE") == \
               pkg.make_grant_key("analytics.public.orders", "select", "table")

    def test_quoted_and_unquoted_names_agree(self, pkg):
        # dbt renders '"ANALYTICS"."PUBLIC"."ORDERS"'; Snowflake reports the same object
        # as 'ANALYTICS.PUBLIC.ORDERS'.
        assert pkg.make_grant_key('"ANALYTICS"."PUBLIC"."ORDERS"', "SELECT", "TABLE") == \
               pkg.make_grant_key("ANALYTICS.PUBLIC.ORDERS", "SELECT", "TABLE")

    def test_partially_quoted_names_agree(self, pkg):
        assert pkg.make_grant_key('ANALYTICS."PUBLIC".ORDERS', "SELECT", "TABLE") == \
               pkg.make_grant_key("ANALYTICS.PUBLIC.ORDERS", "SELECT", "TABLE")

    def test_tolerates_surrounding_whitespace(self, pkg):
        assert pkg.make_grant_key("  analytics  ", "USAGE", "DATABASE") == \
               pkg.make_grant_key("analytics", "USAGE", "DATABASE")

    def test_different_objects_stay_distinct(self, pkg):
        keys = {
            pkg.make_grant_key("analytics.public.orders", "SELECT", "TABLE"),
            pkg.make_grant_key("analytics.public.customers", "SELECT", "TABLE"),
            pkg.make_grant_key("analytics.public", "USAGE", "SCHEMA"),
            pkg.make_grant_key("analytics", "USAGE", "DATABASE"),
        }
        assert len(keys) == 4

    def test_privilege_and_type_are_part_of_the_key(self, pkg):
        assert pkg.make_grant_key("a", "SELECT", "TABLE") != pkg.make_grant_key("a", "USAGE", "TABLE")
        assert pkg.make_grant_key("a", "USAGE", "SCHEMA") != pkg.make_grant_key("a", "USAGE", "DATABASE")

    def test_accepts_any_number_of_parts(self, pkg):
        assert pkg.make_grant_key("a") == "a"
        assert pkg.make_grant_key() == ""


class TestQuotedProjectDoesNotChurn:
    """End-to-end: a project with quoting enabled, already fully granted in Snowflake,
    must produce an empty plan."""

    def _in_sync_share(self, ctx):
        ctx.quote_identifiers = True
        ctx.nodes = [make_node("model.p.orders", "orders", {"shares": ["partner_share"]})]
        ctx.vars["snowflake_shares"] = {"partner_share": {}}
        ctx.on_query(r"SHOW SHARES", [{"name": "A.B.PARTNER_SHARE", "kind": "OUTBOUND"}])
        ctx.on_query(r"SHOW GRANTS TO SHARE", [
            {"privilege": "USAGE", "granted_on": "DATABASE", "name": "ANALYTICS"},
            {"privilege": "USAGE", "granted_on": "SCHEMA", "name": "ANALYTICS.PUBLIC"},
            {"privilege": "SELECT", "granted_on": "TABLE", "name": "ANALYTICS.PUBLIC.ORDERS"},
        ])
        ctx.grant_role_privileges(ALL_SHARE_PRIVILEGES)
        return ctx

    def test_relation_renders_quoted(self, ctx, pkg):
        self._in_sync_share(ctx)
        desired = pkg.get_desired_grants({"partner_share": {}})
        assert any(g["object"] == '"analytics"."public"."orders"'
                   for g in desired["partner_share"].values())

    def test_plan_is_empty(self, ctx, pkg):
        self._in_sync_share(ctx)
        plan = pkg.build_share_plan({"partner_share": {}})["partner_share"]
        assert plan["to_add"] == []
        assert plan["to_revoke"] == []

    def test_no_ddl_is_executed(self, ctx, pkg):
        self._in_sync_share(ctx)
        pkg.process_shares()
        assert ctx.ddl == []

    def test_reports_nothing_to_do(self, ctx, pkg):
        self._in_sync_share(ctx)
        pkg.process_shares()
        assert "nothing to do" in ctx.log_text

    def test_a_genuinely_missing_grant_is_still_detected(self, ctx, pkg):
        # Guard against the fix over-matching and hiding real work.
        self._in_sync_share(ctx)
        ctx.nodes.append(make_node("model.p.customers", "customers", {"shares": ["partner_share"]}))
        plan = pkg.build_share_plan({"partner_share": {}})["partner_share"]
        assert [g["object"] for g in plan["to_add"]] == ['"analytics"."public"."customers"']

    def test_a_genuinely_stale_grant_is_still_detected(self, ctx, pkg):
        self._in_sync_share(ctx)
        ctx.nodes = []
        plan = pkg.build_share_plan({"partner_share": {}})["partner_share"]
        assert len(plan["to_revoke"]) == 3
