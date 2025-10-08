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
  {% set query %}
    DESCRIBE SHARE {{ share_name }}
  {% endset %}

  {% set results = run_query(query) %}

  {% if execute %}
    {% set config = {
      'accounts': [],
      'share_restrictions': false
    } %}

    {% for row in results %}
      {% set kind = row['kind'] %}
      {% set name = row['name'] %}

      {# Extract accounts from the results #}
      {% if kind == 'ACCOUNT' %}
        {% do config['accounts'].append(name) %}
      {% endif %}

      {# Check for share restrictions (this may vary based on Snowflake version) #}
      {% if kind == 'SHARE_RESTRICTIONS' and name == 'true' %}
        {% do config.update({'share_restrictions': true}) %}
      {% endif %}
    {% endfor %}

    {{ return(config) }}
  {% endif %}

  {{ return({}) }}
{% endmacro %}
