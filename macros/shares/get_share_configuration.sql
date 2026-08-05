{#
  Retrieves the current configuration of a Snowflake share.

  Args:
    share_name (str): Name of the share to describe

  Returns:
    dict: Dictionary with 'accounts' (list) and 'share_restrictions' (bool)

  Description:
    Uses DESCRIBE SHARE to retrieve current share configuration.
    Extracts:
    - List of accounts the share is shared with
    - Share restrictions setting (true/false)
#}
{% macro get_share_configuration(share_name) %}
  {% if not execute %}
    {{ return({}) }}
  {% endif %}

  {% set share = dbt_share_flake.validate_identifier(share_name, 'share name') %}

  {% set query %}
    DESCRIBE SHARE {{ share }}
  {% endset %}

  {% set results = run_query(query) %}

  {% set config = {
    'accounts': [],
    'share_restrictions': false
  } %}

  {% for row in results %}
    {% set kind = row['kind'] %}
    {% set object_name = row['name'] %}

    {# Extract accounts from the results #}
    {% if kind == 'ACCOUNT' %}
      {% do config['accounts'].append(object_name) %}
    {% endif %}

    {# Check for share restrictions (this may vary based on Snowflake version) #}
    {% if kind == 'SHARE_RESTRICTIONS' and object_name == 'true' %}
      {% do config.update({'share_restrictions': true}) %}
    {% endif %}
  {% endfor %}

  {{ return(config) }}
{% endmacro %}
