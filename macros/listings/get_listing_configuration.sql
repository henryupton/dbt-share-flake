{#
  Queries the current configuration of a Snowflake listing.

  Args:
    listing_name (str): Name of the listing to query

  Returns:
    dict: Current listing configuration including title, description, and associated share

  Description:
    Uses DESCRIBE LISTING to retrieve the current configuration.
    Parses the result to extract metadata for comparison with desired state.
#}
{% macro get_listing_configuration(listing_name) %}
  {% if execute %}
    {% set listing = dbt_share_flake.validate_identifier(listing_name, 'listing name') %}
    {% set query %}
      DESCRIBE LISTING {{ listing }}
    {% endset %}

    {% set results = run_query(query) %}
    {% set config = {} %}

    {% for row in results %}
      {% set property = row['property'] %}
      {% set value = row['value'] %}

      {% if property == 'title' %}
        {% do config.update({'title': value}) %}
      {% elif property == 'description' %}
        {% do config.update({'description': value}) %}
      {% elif property == 'share' %}
        {% do config.update({'share': value}) %}
      {% endif %}
    {% endfor %}

    {{ return(config) }}
  {% endif %}

  {{ return({}) }}
{% endmacro %}
