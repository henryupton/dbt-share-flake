"""Desired grant derivation, ordering, and plan construction."""
from macro_harness import ALL_SHARE_PRIVILEGES, make_node


def keys_of(desired, share="partner_share"):
    return sorted(desired[share].keys())


class TestGetDesiredGrants:
    def test_covers_database_schema_and_relation(self, ctx, pkg):
        ctx.nodes = [make_node("model.p.orders", "orders", {"shares": ["partner_share"]})]
        desired = pkg.get_desired_grants({"partner_share": {}})
        objects = sorted(g["object"] for g in desired["partner_share"].values())
        assert objects == ["analytics", "analytics.public", "analytics.public.orders"]

    def test_ignores_models_without_share_metadata(self, ctx, pkg):
        ctx.nodes = [make_node("model.p.internal", "internal", {})]
        assert pkg.get_desired_grants({"partner_share": {}}) == {"partner_share": {}}

    def test_view_materialization_yields_a_view_grant(self, ctx, pkg):
        ctx.nodes = [make_node("model.p.c", "c", {"shares": ["s"]}, materialized="view")]
        desired = pkg.get_desired_grants({"s": {}})
        relation = [g for g in desired["s"].values() if g["object"].endswith(".c")][0]
        assert relation["type"] == "VIEW"

    def test_table_like_materializations_yield_a_table_grant(self, ctx, pkg):
        ctx.nodes = [make_node("model.p.t", "t", {"shares": ["s"]}, materialized="incremental")]
        desired = pkg.get_desired_grants({"s": {}})
        relation = [g for g in desired["s"].values() if g["object"].endswith(".t")][0]
        assert relation["type"] == "TABLE"

    def test_snapshots_are_eligible(self, ctx, pkg):
        ctx.nodes = [make_node("snapshot.p.s", "s", {"shares": ["x"]}, resource_type="snapshot")]
        assert len(pkg.get_desired_grants({"x": {}})["x"]) == 3

    def test_listing_metadata_maps_to_the_generated_share(self, ctx, pkg):
        ctx.nodes = [make_node("model.p.o", "o", {"listings": ["my_listing"]})]
        desired = pkg.get_desired_grants({"my_listing_share": {}})
        assert len(desired["my_listing_share"]) == 3

    def test_undefined_share_warns_and_grants_nothing(self, ctx, pkg):
        ctx.nodes = [make_node("model.p.o", "o", {"shares": ["typo_share"]})]
        desired = pkg.get_desired_grants({"partner_share": {}})
        assert desired["partner_share"] == {}
        assert any("typo_share" in w for w in ctx.warnings)

    def test_uses_the_alias_when_set(self, ctx, pkg):
        ctx.nodes = [make_node("model.p.o", "o", {"shares": ["s"]}, alias="renamed")]
        desired = pkg.get_desired_grants({"s": {}})
        assert any(g["object"] == "analytics.public.renamed" for g in desired["s"].values())


class TestGrantProvenance:
    """Each grant records which nodes asked for it, so a failed model can hold back only
    what nothing else needs."""

    def test_shared_schema_grant_records_every_requesting_model(self, ctx, pkg):
        ctx.nodes = [
            make_node("model.p.orders", "orders", {"shares": ["partner_share"]}),
            make_node("model.p.customers", "customers", {"shares": ["partner_share"]}),
        ]
        desired = pkg.get_desired_grants({"partner_share": {}})
        schema_grant = [g for g in desired["partner_share"].values() if g["type"] == "SCHEMA"][0]
        assert sorted(schema_grant["nodes"]) == ["model.p.customers", "model.p.orders"]

    def test_relation_grant_records_only_its_own_model(self, ctx, pkg):
        ctx.nodes = [
            make_node("model.p.orders", "orders", {"shares": ["partner_share"]}),
            make_node("model.p.customers", "customers", {"shares": ["partner_share"]}),
        ]
        desired = pkg.get_desired_grants({"partner_share": {}})
        orders = [g for g in desired["partner_share"].values()
                  if g["object"] == "analytics.public.orders"][0]
        assert orders["nodes"] == ["model.p.orders"]


class TestOrderGrants:
    GRANTS = [
        {"object": "db.sc.t", "privilege": "SELECT", "type": "TABLE"},
        {"object": "db.sc", "privilege": "USAGE", "type": "SCHEMA"},
        {"object": "db", "privilege": "USAGE", "type": "DATABASE"},
    ]

    def test_containers_come_first_when_granting(self, pkg):
        assert [g["type"] for g in pkg.order_grants(self.GRANTS)] == ["DATABASE", "SCHEMA", "TABLE"]

    def test_containers_come_last_when_revoking(self, pkg):
        ordered = pkg.order_grants(self.GRANTS, reverse=True)
        assert [g["type"] for g in ordered] == ["TABLE", "SCHEMA", "DATABASE"]

    def test_loses_nothing(self, pkg):
        assert len(pkg.order_grants(self.GRANTS)) == len(self.GRANTS)

    def test_handles_an_empty_list(self, pkg):
        assert pkg.order_grants([]) == []


class TestBuildSharePlan:
    def _existing_share(self, ctx, grants):
        ctx.on_query(r"SHOW SHARES", [{"name": "MYORG.A.PARTNER_SHARE", "kind": "OUTBOUND"}])
        ctx.on_query(r"SHOW GRANTS TO SHARE", grants)
        ctx.grant_role_privileges(ALL_SHARE_PRIVILEGES)

    def test_marks_a_missing_share_for_creation(self, ctx, pkg):
        ctx.on_query(r"SHOW SHARES", [])
        plan = pkg.build_share_plan({"partner_share": {}})
        assert plan["partner_share"]["to_create"] is True
        assert plan["partner_share"]["exists"] is False

    def test_diffs_against_existing_grants(self, ctx, pkg):
        ctx.nodes = [make_node("model.p.orders", "orders", {"shares": ["partner_share"]})]
        self._existing_share(ctx, [
            {"privilege": "USAGE", "granted_on": "DATABASE", "name": "ANALYTICS"},
            {"privilege": "SELECT", "granted_on": "TABLE", "name": "ANALYTICS.PUBLIC.LEGACY"},
        ])
        plan = pkg.build_share_plan({"partner_share": {}})["partner_share"]
        assert sorted(g["object"] for g in plan["to_add"]) == [
            "analytics.public", "analytics.public.orders"]
        assert [g["object"] for g in plan["to_revoke"]] == ["ANALYTICS.PUBLIC.LEGACY"]

    def test_no_changes_when_already_in_sync(self, ctx, pkg):
        ctx.nodes = [make_node("model.p.orders", "orders", {"shares": ["partner_share"]})]
        self._existing_share(ctx, [
            {"privilege": "USAGE", "granted_on": "DATABASE", "name": "ANALYTICS"},
            {"privilege": "USAGE", "granted_on": "SCHEMA", "name": "ANALYTICS.PUBLIC"},
            {"privilege": "SELECT", "granted_on": "TABLE", "name": "ANALYTICS.PUBLIC.ORDERS"},
        ])
        plan = pkg.build_share_plan({"partner_share": {}})["partner_share"]
        assert plan["to_add"] == [] and plan["to_revoke"] == []

    def test_normalises_table_variants_when_diffing(self, ctx, pkg):
        # SHOW GRANTS reports 'ICEBERG TABLE'; GRANT syntax needs plain 'TABLE'. If these
        # did not normalise to the same key the grant would churn on every run.
        ctx.nodes = [make_node("model.p.orders", "orders", {"shares": ["partner_share"]})]
        self._existing_share(ctx, [
            {"privilege": "USAGE", "granted_on": "DATABASE", "name": "ANALYTICS"},
            {"privilege": "USAGE", "granted_on": "SCHEMA", "name": "ANALYTICS.PUBLIC"},
            {"privilege": "SELECT", "granted_on": "ICEBERG TABLE", "name": "ANALYTICS.PUBLIC.ORDERS"},
        ])
        plan = pkg.build_share_plan({"partner_share": {}})["partner_share"]
        assert plan["to_add"] == [] and plan["to_revoke"] == []

    def test_holds_back_grants_for_a_failed_model(self, ctx, pkg):
        ctx.nodes = [
            make_node("model.p.orders", "orders", {"shares": ["partner_share"]}),
            make_node("model.p.customers", "customers", {"shares": ["partner_share"]}),
        ]
        self._existing_share(ctx, [])
        plan = pkg.build_share_plan({"partner_share": {}}, ["model.p.orders"])["partner_share"]

        assert [g["object"] for g in plan["held_back"]] == ["analytics.public.orders"]
        added = [g["object"] for g in plan["to_add"]]
        assert "analytics.public.customers" in added
        # The healthy model still needs its containers.
        assert "analytics" in added and "analytics.public" in added

    def test_holds_back_containers_when_every_model_failed(self, ctx, pkg):
        ctx.nodes = [make_node("model.p.orders", "orders", {"shares": ["partner_share"]})]
        self._existing_share(ctx, [])
        plan = pkg.build_share_plan({"partner_share": {}}, ["model.p.orders"])["partner_share"]
        assert plan["to_add"] == []
        assert len(plan["held_back"]) == 3

    def test_skips_share_configuration_when_alter_is_off(self, ctx, pkg):
        self._existing_share(ctx, [])
        plan = pkg.build_share_plan({"partner_share": {"accounts": ["ABC12345"]}})
        assert plan["partner_share"]["config_diff"] is None
        assert ctx.statements_matching(r"DESCRIBE SHARE") == []

    def test_diffs_share_configuration_for_a_new_share(self, ctx, pkg):
        ctx.on_query(r"SHOW SHARES", [])
        plan = pkg.build_share_plan({"partner_share": {"accounts": ["ABC12345"]}})
        assert plan["partner_share"]["config_diff"]["accounts_to_add"] == ["ABC12345"]

    def test_tolerates_a_share_configured_with_no_settings(self, ctx, pkg):
        # `my_share:` with nothing under it parses as None.
        ctx.on_query(r"SHOW SHARES", [])
        plan = pkg.build_share_plan({"my_share": None})
        assert plan["my_share"]["to_create"] is True


class TestCountPlanRevokes:
    def test_sums_across_shares(self, ctx, pkg):
        plan = {
            "a": {"to_revoke": [1, 2]},
            "b": {"to_revoke": [3]},
        }
        assert pkg.count_plan_revokes(plan) == 3

    def test_zero_for_an_empty_plan(self, pkg):
        assert pkg.count_plan_revokes({}) == 0
