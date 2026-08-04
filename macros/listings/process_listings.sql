{#
  Listings module entrypoint for Snowflake listing management.

  Args:
    None - Reads configuration from snowflake_listings variable

  Returns:
    dict: Share configuration for auto-generated shares (for injection into shares workflow)

  Description:
    Creates the underlying share for each listing, then the listing itself, then
    optionally reconciles listing metadata.

    Under snowflake_sharing_dry_run the intended DDL is logged and nothing is executed.
    The auto-generated share configuration is still returned so the shares workflow can
    produce a complete plan for shares that do not exist yet.
#}
{% macro process_listings() %}
  {% if not dbt_share_flake.should_run() %}
    {{ return({}) }}
  {% endif %}

  {% set listings_config = var('snowflake_listings', none) %}
  {% if not listings_config %}
    {{ return({}) }}
  {% endif %}

  {% set dry_run = var('snowflake_sharing_dry_run', false) %}

  {% if var('snowflake_listings_check_privileges', true) %}
    {% set required_privileges = ['CREATE LISTING', 'CREATE SHARE'] %}
    {% do dbt_share_flake.check_required_privileges(required_privileges) %}
  {% endif %}

  {% for listing_name, listing_settings in listings_config.items() %}
    {% set listing = dbt_share_flake.validate_identifier(listing_name, 'listing name') %}
    {% set share_name = listing ~ '_share' %}

    {% if not dbt_share_flake.share_exists(share_name) %}
      {{ log("dbt-share-flake: " ~ ("[dry run] " if dry_run else "") ~ "creating share " ~ share_name ~ " for listing " ~ listing, info=True) }}
      {% if not dry_run %}
        {% do run_query(dbt_share_flake.get_create_share_sql(share_name)) %}
      {% endif %}
    {% endif %}

    {% if not dbt_share_flake.listing_exists(listing) %}
      {% set create_listing_sql = dbt_share_flake.get_create_listing_sql(listing, share_name, listing_settings) %}
      {{ log("dbt-share-flake: " ~ ("[dry run] " if dry_run else "") ~ "creating organization listing " ~ listing, info=True) }}
      {% if not dry_run %}
        {% do run_query(create_listing_sql) %}
      {% endif %}
    {% elif var('snowflake_listings_alter_listing', false) %}
      {% set existing_config = dbt_share_flake.get_listing_configuration(listing) %}
      {% do dbt_share_flake.update_listing_configuration(listing, listing_settings, existing_config, dry_run=dry_run) %}
    {% endif %}
  {% endfor %}

  {{ return(dbt_share_flake.build_share_config(listings_config)) }}
{% endmacro %}
