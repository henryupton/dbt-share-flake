{#
  Test macro to verify listing SQL generation
  Run with: dbt run-operation test_listing_sql_generation
#}
{% macro test_listing_sql_generation() %}

  {% set test_config = {
    'title': 'Test Listing',
    'description': 'Test description',
    'organization_profile': 'INTERNAL',
    'organization_targets': {
      'discovery': [
        {'account': 'ABC123', 'roles': ['ANALYST_ROLE']}
      ],
      'access': [
        {'account': 'ABC123', 'roles': ['ANALYST_ROLE']}
      ]
    },
    'support_contact': 'test@example.com',
    'approver_contact': 'approver@example.com',
    'locations': {
      'access_regions': [
        {'name': 'PUBLIC.AWS_US_WEST_2'}
      ]
    }
  } %}

  {% set manifest = dbt_share_flake.build_listing_manifest(test_config) %}
  {% set create_sql = dbt_share_flake.get_create_listing_sql('test_listing', 'test_share', test_config) %}

  {{ log("=== Generated YAML Manifest ===", info=True) }}
  {{ log(manifest, info=True) }}
  {{ log("", info=True) }}
  {{ log("=== Generated CREATE SQL ===", info=True) }}
  {{ log(create_sql, info=True) }}

  {# Verify expected content #}
  {% if 'CREATE ORGANIZATION LISTING' not in create_sql %}
    {{ exceptions.raise_compiler_error("SQL should contain 'CREATE ORGANIZATION LISTING'") }}
  {% endif %}

  {% if 'SHARE test_share AS' not in create_sql %}
    {{ exceptions.raise_compiler_error("SQL should contain 'SHARE test_share AS'") }}
  {% endif %}

  {% if 'organization_profile: "INTERNAL"' not in manifest %}
    {{ exceptions.raise_compiler_error("Manifest should contain organization_profile") }}
  {% endif %}

  {{ log("✓ All SQL generation tests passed!", info=True) }}

{% endmacro %}
