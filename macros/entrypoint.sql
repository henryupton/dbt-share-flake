{#
  Main entrypoint for Snowflake share and listing management.

  Args:
    None - Reads configuration from snowflake_shares and snowflake_listings variables

  Returns:
    str: Empty string, so the macro is safe to use in an on-run-end hook

  Description:
    This is the main entrypoint macro called by the on-run-end hook.
    It orchestrates the complete workflow:
    1. Process listings first (if configured)
       - Creates underlying shares for listings
       - Creates/updates listings
       - Builds share configuration for auto-generated shares
    2. Process shares second (configured + auto-generated)
       - Manages grants to all shares (from both snowflake_shares and listings)
       - Updates share accounts/restrictions

    This ensures listings create their underlying shares first, then all grant
    management happens in a single pass through the shares workflow.

    The run gate lives in should_run() so that the entrypoint, process_shares and
    process_listings all agree on when it is safe to touch anything.
#}
{% macro entrypoint() %}
  {% if not dbt_share_flake.should_run() %}
    {{ return('') }}
  {% endif %}

  {% if var('snowflake_sharing_dry_run', false) %}
    {{ log("dbt-share-flake: snowflake_sharing_dry_run is enabled, no changes will be made", info=True) }}
  {% endif %}

  {# Step 1: Process listings, get auto-generated share config #}
  {% set listing_shares = {} %}
  {% if var('snowflake_listings', none) %}
    {% set listing_shares = dbt_share_flake.process_listings() %}
  {% endif %}

  {# Step 2: Merge configured shares with auto-generated shares #}
  {% set configured_shares = var('snowflake_shares', {}) or {} %}
  {% set all_shares = configured_shares | combine(listing_shares) %}

  {# Step 3: Process all shares (configured + auto-generated) #}
  {% if all_shares %}
    {% do dbt_share_flake.process_shares(shares_config=all_shares) %}
  {% else %}
    {{ log("dbt-share-flake: no shares or listings configured", info=True) }}
  {% endif %}

  {{ return('') }}
{% endmacro %}
