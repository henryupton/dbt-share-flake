{#
  Checks if a Snowflake share exists.

  Args:
    share_name (str): Name of the share to check

  Returns:
    bool: True if the share exists, False otherwise

  Description:
    Uses SHOW SHARES LIKE to check for the existence of a share.
    Returns False if the query returns no results.
#}
{% macro share_exists(share_name) %}
  {% set query %}
    SHOW SHARES LIKE '{{ share_name }}'
  {% endset %}

  {% set results = run_query(query) %}

  {% if execute %}
    {% if results and results.rows | length > 0 %}
      {{ return(true) }}
    {% else %}
      {{ return(false) }}
    {% endif %}
  {% endif %}

  {{ return(false) }}
{% endmacro %}
