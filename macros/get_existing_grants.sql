{#
  Queries Snowflake for existing grants on a share.

  Args:
    share_name (str): Name of the share to query

  Returns:
    dict: Dictionary structure {grant_key: grant_info}
          where grant_info contains object, privilege, and type

  Description:
    Uses SHOW GRANTS TO SHARE to retrieve all existing grants.
    Filters to only USAGE and SELECT privileges.
    Returns grants indexed by grant_key for easy comparison.
#}
{% macro get_existing_grants(share_name) %}
  {% if execute %}
    {% set query %}
      SHOW GRANTS TO SHARE {{ share_name }} ->> SELECT "privilege", "granted_on", "name" FROM $1 WHERE "privilege" IN ('USAGE', 'SELECT')
    {% endset %}
    {% set results = run_query(query) %}
    {% set grants = {} %}

    {% for row in results %}
      {% set privilege = row['privilege'] %}
      {% set granted_on = row['granted_on'] %}
      {% set name = row['name'] %}

      {# Normalize object type for grant/revoke syntax (e.g., ICEBERG TABLE -> TABLE) #}
      {% set normalized_type = dbt_share_flake.normalize_object_type(granted_on) %}
      {% set grant_key = dbt_share_flake.make_grant_key(name, privilege, normalized_type) %}
      {% do grants.update({grant_key: {'object': name, 'privilege': privilege, 'type': normalized_type}}) %}
    {% endfor %}

    {{ return(grants) }}
  {% else %}
    {{ return({}) }}
  {% endif %}
{% endmacro %}
