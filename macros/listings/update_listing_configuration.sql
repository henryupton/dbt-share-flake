{#
  Updates a Snowflake organization listing configuration if changes are detected.

  Args:
    listing_name (str): Name of the listing to update
    desired_config (dict): Desired listing configuration
    existing_config (dict): Current listing configuration
    dry_run (bool): When true, log the statement without executing it

  Returns:
    str: Empty string, so the macro is safe to call from inside a hook

  Description:
    Compares desired vs existing listing metadata.
    If differences are found, generates and executes ALTER ORGANIZATION LISTING AS.
    This is controlled by the snowflake_listings_alter_listing variable.
#}
{% macro update_listing_configuration(listing_name, desired_config, existing_config, dry_run=false) %}
  {% if not execute %}
    {{ return('') }}
  {% endif %}

  {% set listing = dbt_share_flake.validate_identifier(listing_name, 'listing name') %}
  {% set needs_update = false %}

  {% if desired_config.get('title', '') != existing_config.get('title', '') %}
    {% set needs_update = true %}
  {% endif %}

  {% if desired_config.get('description', '') != existing_config.get('description', '') %}
    {% set needs_update = true %}
  {% endif %}

  {% if desired_config.get('organization_profile', 'INTERNAL') != existing_config.get('organization_profile', '') %}
    {% set needs_update = true %}
  {% endif %}

  {# DESCRIBE LISTING does not report targets, contacts or locations in a form that can #}
  {# be compared field by field, so their presence forces a re-apply. ALTER ORGANIZATION #}
  {# LISTING AS is a full replacement of the manifest and is idempotent, so re-applying #}
  {# is safe, just noisy. #}
  {% if desired_config.get('organization_targets') or desired_config.get('support_contact')
        or desired_config.get('approver_contact') or desired_config.get('locations') %}
    {% set needs_update = true %}
  {% endif %}

  {% if needs_update %}
    {% set manifest = dbt_share_flake.build_listing_manifest(desired_config) %}
    {% set alter_sql %}
      ALTER ORGANIZATION LISTING {{ listing }} AS
      $$
{{ manifest }}
      $$
    {% endset %}

    {{ log("dbt-share-flake: " ~ ("[dry run] " if dry_run else "") ~ "updating organization listing " ~ listing, info=True) }}
    {% if not dry_run %}
      {% do run_query(alter_sql) %}
    {% endif %}
  {% endif %}

  {{ return('') }}
{% endmacro %}
