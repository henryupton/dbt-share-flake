{#
  Generates SQL to create a Snowflake organization listing.

  Args:
    listing_name (str): Name of the listing to create
    share_name (str): Name of the underlying share (e.g., {listing_name}_share)
    listing_config (dict): Listing configuration with organization listing fields

  Returns:
    str: SQL CREATE ORGANIZATION LISTING statement

  Description:
    Generates a CREATE ORGANIZATION LISTING statement for internal/organizational use.
    Uses YAML manifest for listing metadata including organization_profile,
    organization_targets, contacts, and locations.
#}
{% macro get_create_listing_sql(listing_name, share_name, listing_config) %}
  {% set listing = dbt_share_flake.validate_identifier(listing_name, 'listing name') %}
  {% set share = dbt_share_flake.validate_identifier(share_name, 'share name') %}
  {% set manifest = dbt_share_flake.build_listing_manifest(listing_config) %}

  {% set create_sql %}
    CREATE ORGANIZATION LISTING {{ listing }}
    SHARE {{ share }} AS
    $$
{{ manifest }}
    $$
  {% endset %}

  {{ return(create_sql) }}
{% endmacro %}
