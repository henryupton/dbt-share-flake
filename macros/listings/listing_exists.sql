{#
  Checks if a Snowflake listing exists.

  Args:
    listing_name (str): Name of the listing to check

  Returns:
    bool: True if listing exists, False otherwise

  Description:
    Uses SHOW LISTINGS LIKE to narrow the result set, then matches exactly in Jinja.
    As with shares, the LIKE pattern can over-match because '_' is a wildcard, and a
    false positive would skip creation entirely. CREATE ORGANIZATION LISTING has no
    IF NOT EXISTS form, so a false negative is not free either: the exact match keeps
    both directions honest.
#}
{% macro listing_exists(listing_name) %}
  {% if not execute %}
    {{ return(false) }}
  {% endif %}

  {% set name = dbt_share_flake.validate_identifier(listing_name, 'listing name') %}

  {% set query %}
    SHOW LISTINGS LIKE '{{ name }}'
  {% endset %}

  {% set results = run_query(query) %}

  {% if results %}
    {% for row in results %}
      {% if dbt_share_flake.identifier_matches(row.get('name', ''), name) %}
        {{ return(true) }}
      {% endif %}
    {% endfor %}
  {% endif %}

  {{ return(false) }}
{% endmacro %}
