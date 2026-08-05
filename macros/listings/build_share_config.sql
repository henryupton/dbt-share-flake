{#
  Builds share configuration for auto-generated listing shares from dbt graph.

  Args:
    listings_config (dict): Dictionary of listing configurations

  Returns:
    dict: Share configuration for auto-generated shares (format: {share_name: {models: [list]}})

  Description:
    Iterates through the dbt graph to find models with meta.listings.
    For each listing referenced in model metadata:
    - Maps the model to the auto-generated share (e.g., my_listing -> my_listing_share)
    - Builds a share configuration dict compatible with the shares workflow

    This share config is then injected into the shares workflow so that grant
    management happens in a single pass for both configured and auto-generated shares.
#}
{% macro build_share_config(listings_config) %}
  {% if execute %}
    {% set share_config = {} %}

    {# Initialize share config for each listing #}
    {% for listing_name in listings_config.keys() %}
      {% set share_name = listing_name ~ '_share' %}
      {% do share_config.update({share_name: {}}) %}
    {% endfor %}

    {# Iterate through dbt graph to find models with meta.listings #}
    {% for node in graph.nodes.values() %}
      {% if node.resource_type in ['model', 'snapshot'] %}
        {% set model_listings = node.meta.get('listings', []) %}

        {% if model_listings %}
          {% for listing_name in model_listings %}
            {% if listing_name in listings_config.keys() %}
              {# This model should be granted to the auto-generated share #}
              {# The shares workflow will handle the actual grant logic #}
              {# We just need to mark that this share exists for this listing #}
              {% set share_name = listing_name ~ '_share' %}

              {# Ensure share exists in config (should already from initialization) #}
              {% if share_name not in share_config.keys() %}
                {% do share_config.update({share_name: {}}) %}
              {% endif %}
            {% else %}
              {{ exceptions.warn("Warning: Listing '" ~ listing_name ~ "' referenced in model '" ~ node.name ~ "' but not defined in snowflake_listings variable") }}
            {% endif %}
          {% endfor %}
        {% endif %}
      {% endif %}
    {% endfor %}

    {{ return(share_config) }}
  {% endif %}

  {{ return({}) }}
{% endmacro %}
