"""The rails that stop a run from quietly breaking a live consumer.

Desired state is derived from the whole dbt graph, so anything that narrows the graph
without narrowing intent makes still-wanted grants look like deletions. Revocation is the
only operation here that a consumer notices, so it is the one that gets guarded.
"""
import pytest
from types import SimpleNamespace

from macro_harness import (
    ALL_SHARE_PRIVILEGES,
    CompilerError,
    build_package,
    make_node,
    make_result,
)


class TestShouldRun:
    def test_allows_an_ordinary_run(self, pkg):
        assert pkg.should_run() is True

    def test_honours_the_kill_switch(self, ctx, pkg):
        ctx.vars["snowflake_sharing_enabled"] = False
        assert pkg.should_run() is False

    @pytest.mark.parametrize("command", ["run", "build", "snapshot", "run-operation"])
    def test_allows_commands_that_materialise_relations(self, ctx, pkg, command):
        ctx.flags = SimpleNamespace(WHICH=command)
        assert pkg.should_run() is True

    @pytest.mark.parametrize("command", ["docs generate", "test", "compile", "seed", "parse"])
    def test_blocks_other_commands(self, ctx, pkg, command):
        ctx.flags = SimpleNamespace(WHICH=command)
        assert pkg.should_run() is False

    def test_blocks_a_target_outside_the_allowlist(self, ctx, pkg):
        ctx.vars["snowflake_sharing_targets"] = ["prod"]
        ctx.target = SimpleNamespace(name="dev")
        assert pkg.should_run() is False
        assert "not in" in ctx.log_text

    def test_allows_a_target_in_the_allowlist(self, ctx, pkg):
        ctx.vars["snowflake_sharing_targets"] = ["prod", "ci"]
        ctx.target = SimpleNamespace(name="ci")
        assert pkg.should_run() is True

    def test_accepts_a_bare_string_allowlist(self, ctx, pkg):
        ctx.vars["snowflake_sharing_targets"] = "prod"
        assert pkg.should_run() is True

    def test_all_targets_allowed_by_default(self, ctx, pkg):
        ctx.target = SimpleNamespace(name="somebodys_sandbox")
        assert pkg.should_run() is True


class TestIsPartialSelection:
    def test_false_when_the_flags_do_not_exist_at_all(self, pkg):
        # Older dbt versions may not expose these; the check must not raise.
        assert pkg.is_partial_selection() is False

    def test_false_for_a_full_run(self, ctx, pkg):
        ctx.flags = SimpleNamespace(WHICH="run", SELECT=(), EXCLUDE=(), SELECTOR=None)
        assert pkg.is_partial_selection() is False

    @pytest.mark.parametrize("flag", ["SELECT", "EXCLUDE", "SELECTOR"])
    def test_true_for_each_selection_flag(self, ctx, pkg, flag):
        ctx.flags = SimpleNamespace(WHICH="run", **{flag: ("something",)})
        assert pkg.is_partial_selection() is True

    def test_handles_lowercase_spellings(self, ctx, pkg):
        ctx.flags = SimpleNamespace(WHICH="run", select=("my_model",))
        assert pkg.is_partial_selection() is True


class TestGetBlockedNodeIds:
    def test_collects_unsuccessful_nodes_only(self, ctx, pkg):
        ctx.results = [
            make_result("model.p.ok", "success"),
            make_result("model.p.broken", "error"),
            make_result("model.p.downstream", "skipped"),
            make_result("test.p.assertion", "fail"),
            make_result("test.p.warned", "warn"),
        ]
        assert sorted(pkg.get_blocked_node_ids()) == [
            "model.p.broken", "model.p.downstream", "test.p.assertion"]

    def test_empty_for_a_clean_run(self, ctx, pkg):
        ctx.results = [make_result("model.p.ok", "success")]
        assert pkg.get_blocked_node_ids() == []

    def test_copes_with_results_being_absent(self, ctx):
        # `results` is only in scope for on-run-end hooks.
        pkg = build_package(ctx, with_results=False)
        assert pkg.get_blocked_node_ids() == []


class TestDryRun:
    def test_executes_nothing(self, drifted_share, pkg):
        drifted_share.vars["snowflake_sharing_dry_run"] = True
        pkg.process_shares()
        assert drifted_share.ddl == []

    def test_still_logs_the_plan(self, drifted_share, pkg):
        drifted_share.vars["snowflake_sharing_dry_run"] = True
        pkg.process_shares()
        assert "DRY RUN" in drifted_share.log_text
        assert "+ grant" in drifted_share.log_text
        assert "- revoke" in drifted_share.log_text

    def test_shows_the_stale_grant(self, drifted_share, pkg):
        drifted_share.vars["snowflake_sharing_dry_run"] = True
        pkg.process_shares()
        assert "analytics.public.legacy" in drifted_share.log_text


class TestRealRun:
    def test_grants_what_is_missing(self, drifted_share, pkg):
        pkg.process_shares()
        assert drifted_share.statements_matching(
            r"GRANT SELECT ON TABLE analytics.public.orders TO SHARE partner_share")

    def test_revokes_what_is_stale(self, drifted_share, pkg):
        pkg.process_shares()
        assert drifted_share.statements_matching(
            r"REVOKE SELECT ON TABLE ANALYTICS.PUBLIC.LEGACY FROM SHARE partner_share")

    def test_grants_containers_before_contents(self, drifted_share, pkg):
        pkg.process_shares()
        grants = drifted_share.statements_matching(r"^GRANT")
        assert "ON DATABASE" in grants[0]
        assert "ON TABLE" in grants[-1]

    def test_revokes_before_granting(self, drifted_share, pkg):
        pkg.process_shares()
        assert drifted_share.sql.index("REVOKE") < drifted_share.sql.index("GRANT USAGE")

    def test_logs_completion(self, drifted_share, pkg):
        pkg.process_shares()
        assert "share management complete" in drifted_share.log_text


class TestRevokeGuards:
    def test_partial_selection_suppresses_revocation(self, drifted_share, pkg):
        drifted_share.flags = SimpleNamespace(WHICH="run", SELECT=("orders",))
        pkg.process_shares()
        assert drifted_share.statements_matching(r"REVOKE") == []

    def test_partial_selection_still_applies_grants(self, drifted_share, pkg):
        drifted_share.flags = SimpleNamespace(WHICH="run", SELECT=("orders",))
        pkg.process_shares()
        assert drifted_share.statements_matching(r"^GRANT")

    def test_partial_selection_suppression_is_explained(self, drifted_share, pkg):
        drifted_share.flags = SimpleNamespace(WHICH="run", SELECT=("orders",))
        pkg.process_shares()
        assert "--select" in drifted_share.log_text

    def test_partial_selection_suppression_can_be_overridden(self, drifted_share, pkg):
        drifted_share.flags = SimpleNamespace(WHICH="run", SELECT=("orders",))
        drifted_share.vars["snowflake_sharing_revoke_on_partial_selection"] = True
        pkg.process_shares()
        assert drifted_share.statements_matching(r"REVOKE")

    def test_a_failed_node_suppresses_revocation(self, drifted_share, pkg):
        drifted_share.results = [make_result("model.p.unrelated", "error")]
        pkg.process_shares()
        assert drifted_share.statements_matching(r"REVOKE") == []
        assert "did not succeed" in drifted_share.log_text

    def test_a_failing_test_suppresses_revocation(self, drifted_share, pkg):
        drifted_share.results = [make_result("test.p.assertion", "fail")]
        pkg.process_shares()
        assert drifted_share.statements_matching(r"REVOKE") == []

    def test_failure_suppression_can_be_overridden(self, drifted_share, pkg):
        drifted_share.results = [make_result("model.p.unrelated", "error")]
        drifted_share.vars["snowflake_sharing_revoke_after_failure"] = True
        pkg.process_shares()
        assert drifted_share.statements_matching(r"REVOKE")

    def test_allow_revoke_false_suppresses_revocation(self, drifted_share, pkg):
        drifted_share.vars["snowflake_sharing_allow_revoke"] = False
        pkg.process_shares()
        assert drifted_share.statements_matching(r"REVOKE") == []
        assert drifted_share.statements_matching(r"^GRANT")

    def test_a_clean_full_run_revokes(self, drifted_share, pkg):
        drifted_share.results = [make_result("model.p.orders", "success")]
        pkg.process_shares()
        assert drifted_share.statements_matching(r"REVOKE")


class TestRevokeThreshold:
    @pytest.fixture
    def many_stale_grants(self, ctx):
        ctx.nodes = [make_node("model.p.orders", "orders", {"shares": ["partner_share"]})]
        ctx.vars["snowflake_shares"] = {"partner_share": {}}
        ctx.on_query(r"SHOW SHARES", [{"name": "A.B.PARTNER_SHARE", "kind": "OUTBOUND"}])
        ctx.on_query(r"SHOW GRANTS TO SHARE", [
            {"privilege": "SELECT", "granted_on": "TABLE", "name": f"ANALYTICS.PUBLIC.OLD_{i}"}
            for i in range(25)
        ])
        ctx.grant_role_privileges(ALL_SHARE_PRIVILEGES)
        return ctx

    def test_aborts_above_the_default_limit(self, many_stale_grants, pkg):
        with pytest.raises(CompilerError):
            pkg.process_shares()

    def test_changes_nothing_before_aborting(self, many_stale_grants, pkg):
        with pytest.raises(CompilerError):
            pkg.process_shares()
        assert many_stale_grants.ddl == []

    def test_logs_the_plan_before_aborting(self, many_stale_grants, pkg):
        with pytest.raises(CompilerError):
            pkg.process_shares()
        assert "- revoke" in many_stale_grants.log_text

    def test_error_names_the_variable_to_change(self, many_stale_grants, pkg):
        with pytest.raises(CompilerError) as excinfo:
            pkg.process_shares()
        assert "snowflake_sharing_max_revokes" in str(excinfo.value)

    def test_raising_the_limit_allows_the_revocations(self, many_stale_grants, pkg):
        many_stale_grants.vars["snowflake_sharing_max_revokes"] = 100
        pkg.process_shares()
        assert len(many_stale_grants.statements_matching(r"^REVOKE")) == 25

    def test_disabling_the_limit_allows_the_revocations(self, many_stale_grants, pkg):
        many_stale_grants.vars["snowflake_sharing_max_revokes"] = None
        pkg.process_shares()
        assert len(many_stale_grants.statements_matching(r"^REVOKE")) == 25

    def test_suppressed_revokes_do_not_trip_the_threshold(self, many_stale_grants, pkg):
        many_stale_grants.vars["snowflake_sharing_allow_revoke"] = False
        pkg.process_shares()
        assert many_stale_grants.statements_matching(r"REVOKE") == []


class TestHeldBackGrants:
    def test_a_failed_model_does_not_get_granted(self, ctx, pkg):
        ctx.nodes = [
            make_node("model.p.orders", "orders", {"shares": ["partner_share"]}),
            make_node("model.p.customers", "customers", {"shares": ["partner_share"]}),
        ]
        ctx.vars["snowflake_shares"] = {"partner_share": {}}
        ctx.results = [make_result("model.p.orders", "error")]
        ctx.on_query(r"SHOW SHARES", [{"name": "A.B.PARTNER_SHARE", "kind": "OUTBOUND"}])
        ctx.on_query(r"SHOW GRANTS TO SHARE", [])
        ctx.grant_role_privileges(ALL_SHARE_PRIVILEGES)

        pkg.process_shares()

        assert ctx.statements_matching(r"GRANT SELECT ON TABLE analytics.public.orders") == []
        assert ctx.statements_matching(r"GRANT SELECT ON TABLE analytics.public.customers")
        assert "held back" in ctx.log_text


class TestGatedEntrypoints:
    def test_process_shares_does_nothing_when_disabled(self, drifted_share, pkg):
        drifted_share.vars["snowflake_sharing_enabled"] = False
        pkg.process_shares()
        assert drifted_share.executed_sql == []

    def test_process_shares_does_nothing_on_a_blocked_target(self, drifted_share, pkg):
        drifted_share.vars["snowflake_sharing_targets"] = ["prod"]
        drifted_share.target = SimpleNamespace(name="dev")
        pkg.process_shares()
        assert drifted_share.executed_sql == []

    def test_no_shares_configured_is_not_an_error(self, ctx, pkg):
        pkg.process_shares()
        assert ctx.executed_sql == []
        assert "no shares configured" in ctx.log_text

    def test_works_without_the_on_run_end_results_context(self, drifted_share):
        pkg = build_package(drifted_share, with_results=False)
        pkg.process_shares()
        assert drifted_share.statements_matching(r"^GRANT")
        assert drifted_share.statements_matching(r"^REVOKE")
