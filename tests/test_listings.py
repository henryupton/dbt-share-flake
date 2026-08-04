"""Listing manifest building and listing orchestration."""
import pytest

from macro_harness import ALL_LISTING_PRIVILEGES, CompilerError, make_node

FULL_CONFIG = {
    "title": "Internal Analytics Data",
    "description": "For internal BI and reporting",
    "organization_profile": "INTERNAL",
    "organization_targets": {
        "discovery": [{"account": "ABC123", "roles": ["ANALYST_ROLE", "DATA_SCIENTIST"]}],
        "access": [{"account": "ABC123", "roles": ["ANALYST_ROLE"]}],
    },
    "support_contact": "data-team@example.com",
    "approver_contact": "data-governance@example.com",
    "locations": {"access_regions": [{"name": "PUBLIC.AWS_US_WEST_2"}]},
}


class TestBuildListingManifest:
    def test_emits_every_configured_field(self, pkg):
        manifest = pkg.build_listing_manifest(FULL_CONFIG)
        for expected in [
            'title: "Internal Analytics Data"',
            'description: "For internal BI and reporting"',
            'organization_profile: "INTERNAL"',
            "organization_targets:",
            "  discovery:",
            "  access:",
            '    - account: "ABC123"',
            '        - "ANALYST_ROLE"',
            'support_contact: "data-team@example.com"',
            'approver_contact: "data-governance@example.com"',
            "locations:",
            '    - name: "PUBLIC.AWS_US_WEST_2"',
        ]:
            assert expected in manifest, f"missing {expected!r} in:\n{manifest}"

    def test_omits_optional_fields_when_absent(self, pkg):
        manifest = pkg.build_listing_manifest({"title": "T", "description": "D"})
        assert "support_contact" not in manifest
        assert "organization_targets" not in manifest
        assert "locations" not in manifest

    def test_defaults_profile_to_internal(self, pkg):
        manifest = pkg.build_listing_manifest({"title": "T", "description": "D"})
        assert 'organization_profile: "INTERNAL"' in manifest

    def test_accepts_external_profile(self, pkg):
        manifest = pkg.build_listing_manifest({"title": "T", "organization_profile": "EXTERNAL"})
        assert 'organization_profile: "EXTERNAL"' in manifest

    def test_rejects_an_unknown_profile(self, pkg):
        with pytest.raises(CompilerError):
            pkg.build_listing_manifest({"title": "T", "organization_profile": "PUBLIC"})

    def test_escapes_quotes_in_the_title(self, pkg):
        manifest = pkg.build_listing_manifest({"title": 'Nasty "Quoted" Title'})
        assert 'title: "Nasty \\"Quoted\\" Title"' in manifest

    def test_keeps_a_multiline_description_on_one_line(self, pkg):
        manifest = pkg.build_listing_manifest({"title": "T", "description": "Line one\nLine two"})
        assert 'description: "Line one\\nLine two"' in manifest

    def test_rejects_a_dollar_quote_injection(self, pkg):
        with pytest.raises(CompilerError):
            pkg.build_listing_manifest(
                {"title": "T", "description": "$$; DROP SHARE x; SELECT $$"})

    def test_validates_target_accounts(self, pkg):
        with pytest.raises(CompilerError):
            pkg.build_listing_manifest({
                "title": "T",
                "organization_targets": {"discovery": [{"account": "bad account!"}]},
            })

    def test_validates_target_roles(self, pkg):
        with pytest.raises(CompilerError):
            pkg.build_listing_manifest({
                "title": "T",
                "organization_targets": {
                    "discovery": [{"account": "ABC123", "roles": ["r; DROP SHARE x"]}]},
            })

    def test_targets_without_roles_are_allowed(self, pkg):
        manifest = pkg.build_listing_manifest({
            "title": "T",
            "organization_targets": {"discovery": [{"account": "ABC123"}]},
        })
        assert '- account: "ABC123"' in manifest
        assert "roles:" not in manifest


class TestGetCreateListingSql:
    def test_statement_shape(self, pkg):
        sql = pkg.get_create_listing_sql("my_listing", "my_listing_share", FULL_CONFIG)
        assert "CREATE ORGANIZATION LISTING my_listing" in sql
        assert "SHARE my_listing_share AS" in sql
        assert 'title: "Internal Analytics Data"' in sql

    @pytest.mark.parametrize("listing,share", [
        ("x; DROP SHARE y", "s"),
        ("my_listing", "s; DROP SHARE y"),
    ])
    def test_validates_both_identifiers(self, pkg, listing, share):
        with pytest.raises(CompilerError):
            pkg.get_create_listing_sql(listing, share, {"title": "T"})


class TestGetListingConfiguration:
    def test_reads_the_described_properties(self, ctx, pkg):
        ctx.on_query(r"DESCRIBE LISTING", [
            {"property": "title", "value": "Current Title"},
            {"property": "description", "value": "Current Description"},
            {"property": "share", "value": "my_listing_share"},
            {"property": "state", "value": "PUBLISHED"},
        ])
        config = pkg.get_listing_configuration("my_listing")
        assert config == {
            "title": "Current Title",
            "description": "Current Description",
            "share": "my_listing_share",
        }

    def test_empty_when_nothing_is_described(self, ctx, pkg):
        ctx.on_query(r"DESCRIBE LISTING", [])
        assert pkg.get_listing_configuration("my_listing") == {}

    def test_validates_the_listing_name_before_querying(self, ctx, pkg):
        with pytest.raises(CompilerError):
            pkg.get_listing_configuration("x; DROP SHARE y")
        assert ctx.executed_sql == []


class TestUpdateListingConfiguration:
    def test_alters_when_the_title_changed(self, ctx, pkg):
        pkg.update_listing_configuration(
            "my_listing", {"title": "New", "description": "D"}, {"title": "Old", "description": "D"})
        assert ctx.statements_matching(r"ALTER ORGANIZATION LISTING my_listing")

    def test_re_applies_even_when_nothing_changed(self, ctx, pkg):
        """Known limitation, pinned here so a future fix is a deliberate change.

        DESCRIBE LISTING does not report organization_profile, so the comparison is always
        against '' and never matches the configured (or defaulted) value. Configured
        targets, contacts or locations force a re-apply for the same reason. ALTER
        ORGANIZATION LISTING AS replaces the whole manifest and is idempotent, so this is
        noise rather than damage, and it only happens with
        snowflake_listings_alter_listing enabled.
        """
        pkg.update_listing_configuration(
            "my_listing", {"title": "T", "description": "D"}, {"title": "T", "description": "D"})
        assert ctx.statements_matching(r"ALTER ORGANIZATION LISTING my_listing")

    def test_dry_run_logs_without_executing(self, ctx, pkg):
        pkg.update_listing_configuration(
            "my_listing", {"title": "New"}, {"title": "Old"}, dry_run=True)
        assert ctx.executed_sql == []
        assert "[dry run]" in ctx.log_text

    def test_validates_the_listing_name(self, ctx, pkg):
        with pytest.raises(CompilerError):
            pkg.update_listing_configuration("x; DROP SHARE y", {"title": "T"}, {})
        assert ctx.executed_sql == []


class TestBuildShareConfig:
    def test_generates_a_share_per_listing(self, ctx, pkg):
        ctx.nodes = [make_node("model.p.o", "o", {"listings": ["my_listing"]})]
        assert pkg.build_share_config({"my_listing": {}}) == {"my_listing_share": {}}

    def test_generates_shares_for_listings_with_no_models(self, ctx, pkg):
        assert pkg.build_share_config({"a": {}, "b": {}}) == {"a_share": {}, "b_share": {}}

    def test_warns_about_an_undefined_listing(self, ctx, pkg):
        ctx.nodes = [make_node("model.p.o", "o", {"listings": ["typo_listing"]})]
        pkg.build_share_config({"my_listing": {}})
        assert any("typo_listing" in w for w in ctx.warnings)


class TestProcessListings:
    def _configure(self, ctx, share_rows=(), listing_rows=()):
        ctx.vars["snowflake_listings"] = {"my_listing": {"title": "T", "description": "D"}}
        ctx.on_query(r"SHOW SHARES", list(share_rows))
        ctx.on_query(r"SHOW LISTINGS", list(listing_rows))
        ctx.grant_role_privileges(ALL_LISTING_PRIVILEGES)
        return ctx

    def test_creates_the_share_then_the_listing(self, ctx, pkg):
        self._configure(ctx)
        pkg.process_listings()
        assert ctx.sql.index("CREATE SHARE IF NOT EXISTS my_listing_share") < \
               ctx.sql.index("CREATE ORGANIZATION LISTING my_listing")

    def test_returns_the_generated_share_config(self, ctx, pkg):
        self._configure(ctx)
        assert pkg.process_listings() == {"my_listing_share": {}}

    def test_is_idempotent_when_both_already_exist(self, ctx, pkg):
        self._configure(
            ctx,
            share_rows=[{"name": "A.B.MY_LISTING_SHARE", "kind": "OUTBOUND"}],
            listing_rows=[{"name": "MY_LISTING"}],
        )
        pkg.process_listings()
        assert ctx.ddl == []

    def test_alters_an_existing_listing_when_enabled(self, ctx, pkg):
        self._configure(
            ctx,
            share_rows=[{"name": "A.B.MY_LISTING_SHARE", "kind": "OUTBOUND"}],
            listing_rows=[{"name": "MY_LISTING"}],
        )
        ctx.vars["snowflake_listings_alter_listing"] = True
        ctx.on_query(r"DESCRIBE LISTING", [{"property": "title", "value": "Old"},
                                           {"property": "description", "value": "D"}])
        pkg.process_listings()
        assert ctx.statements_matching(r"ALTER ORGANIZATION LISTING my_listing")
        assert ctx.statements_matching(r"CREATE ORGANIZATION LISTING") == []

    def test_does_not_alter_a_listing_it_just_created(self, ctx, pkg):
        self._configure(ctx)
        ctx.vars["snowflake_listings_alter_listing"] = True
        pkg.process_listings()
        assert ctx.statements_matching(r"ALTER ORGANIZATION LISTING") == []

    def test_dry_run_creates_nothing(self, ctx, pkg):
        self._configure(ctx)
        ctx.vars["snowflake_sharing_dry_run"] = True
        pkg.process_listings()
        assert ctx.ddl == []

    def test_dry_run_still_returns_the_share_config(self, ctx, pkg):
        self._configure(ctx)
        ctx.vars["snowflake_sharing_dry_run"] = True
        assert pkg.process_listings() == {"my_listing_share": {}}

    def test_returns_empty_when_no_listings_configured(self, ctx, pkg):
        assert pkg.process_listings() == {}
        assert ctx.executed_sql == []

    def test_validates_the_listing_name(self, ctx, pkg):
        ctx.vars["snowflake_listings"] = {"bad name": {"title": "T"}}
        with pytest.raises(CompilerError):
            pkg.process_listings()

    def test_does_nothing_on_a_blocked_target(self, ctx, pkg):
        self._configure(ctx)
        ctx.vars["snowflake_sharing_targets"] = ["prod"]
        ctx.target = type(ctx.target)(name="dev")
        assert pkg.process_listings() == {}
        assert ctx.executed_sql == []
