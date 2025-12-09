{#
  Main entrypoint for Snowflake share grant management.

  Args:
    None - Reads configuration from snowflake_shares variable

  Returns:
    None - Executes share management workflow

  Description:
    This is the main entrypoint macro called by the on-run-end hook.
    It orchestrates the complete share management workflow:
    1. Validates command context (only runs during run/build/snapshot/run-operation)
    2. Optionally checks for required privileges (controlled by snowflake_shares_check_privileges var)
    3. For each configured share:
       - Creates the share if it doesn't exist
       - Manages grants (adds/revokes based on model metadata)
       - Updates share configuration (accounts and share_restrictions)
#}
{% macro entrypoint() %}
  {% set share_config = var('snowflake_shares', {}) %}

  {% if execute %}
    {# Only run during run, build, run-operation, or snapshot commands #}
    {% set allowed_flags = ['run', 'build', 'run-operation', 'snapshot'] %}
    {% if flags.WHICH not in allowed_flags %}
      {{ log("Skipping share grant management - only runs during: " ~ allowed_flags | join(', '), info=True) }}
      {{ return('') }}
    {% endif %}

    {% if share_config %}
      {# Check for required privileges if enabled #}
      {% set check_privileges = var('snowflake_shares_check_privileges', true) %}
      {% if check_privileges %}
        {% set required_privileges = [
            'CREATE SHARE',
            'IMPORT SHARE',
            'MANAGE GRANTS',
            'MANAGE SHARE TARGET'
        ] %}
        {% set missing_privs = dbt_share_flake.check_required_privileges(required_privileges) %}
      {% endif %}

      {# Iterate through each share and process individually #}
      {% for share_name, share_settings in share_config.items() %}
        {{ log("Processing share: " ~ share_name, info=False) }}

        {# Step 1: Check if share exists, create if not #}
        {% if not dbt_share_flake.share_exists(share_name) %}
          {{ log("Share " ~ share_name ~ " does not exist, creating...", info=True) }}
          {% set create_sql = dbt_share_flake.get_create_share_sql(share_name) %}
          {% do run_query(create_sql) %}
          {{ log("Share " ~ share_name ~ " created successfully", info=True) }}
        {% endif %}

        {# Step 2: Manage grants on the share (databases must be added first) #}
        {# Create a single-share config to pass to grant_to_shares #}
        {% set single_share_config = {share_name: share_settings} %}
        {{ log("Processing Snowflake share grants...", info=True) }}
        {{ dbt_share_flake.grant_to_shares(single_share_config) }}
        {{ log("Snowflake share grants completed successfully!", info=True) }}

        {# Step 3: Update share configuration (accounts and share_restrictions) #}
        {# This must happen after grants because share needs a database first #}
        {% set existing_config = dbt_share_flake.get_share_configuration(share_name) %}
        {{ dbt_share_flake.update_share_configuration(share_name, share_settings, existing_config) }}
      {% endfor %}
    {% else %}
      {{ log("No Snowflake shares configured in snowflake_shares variable", info=True) }}
    {% endif %}
  {% endif %}
{% endmacro %}
