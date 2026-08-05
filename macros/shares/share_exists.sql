{#
  Checks if an outbound Snowflake share exists.

  Args:
    share_name (str): Name of the share to check

  Returns:
    bool: True if the share exists, False otherwise

  Description:
    Uses SHOW SHARES LIKE to narrow the result set, then matches exactly in Jinja.
    The LIKE pattern alone is not sufficient: Snowflake treats '_' as a single
    character wildcard, so 'test_share_1' also matches 'testXshareY1'. A false
    positive there means the share is silently never created. The narrowing pattern is
    deliberately left unescaped because it can only ever over-match, and correctness
    comes from the exact comparison that follows.

    Inbound shares are excluded, since a share imported from another account is not
    something this package can grant on.
#}
{% macro share_exists(share_name) %}
  {% if not execute %}
    {{ return(false) }}
  {% endif %}

  {% set name = dbt_share_flake.validate_identifier(share_name, 'share name') %}

  {% set query %}
    SHOW SHARES LIKE '{{ name }}'
  {% endset %}

  {% set results = run_query(query) %}

  {% if results %}
    {% for row in results %}
      {% set kind = (row.get('kind', '') | string) | upper %}
      {% if kind != 'INBOUND' and dbt_share_flake.identifier_matches(row.get('name', ''), name) %}
        {{ return(true) }}
      {% endif %}
    {% endfor %}
  {% endif %}

  {{ return(false) }}
{% endmacro %}
