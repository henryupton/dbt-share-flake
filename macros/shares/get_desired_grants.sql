{#
  Extracts desired grants from the dbt graph based on model metadata.

  Args:
    share_config (dict): Dictionary mapping share names to their settings

  Returns:
    dict: Nested dictionary structure {share_name: {grant_key: grant_info}}
          where grant_info contains object, privilege, type and nodes

  Description:
    Walks every model and snapshot in the dbt graph exactly once, building the desired
    grant set for all shares at the same time. For each node with a 'shares' or
    'listings' metadata field it records:
    - USAGE on the database
    - USAGE on the schema
    - SELECT on the table/view (based on materialization)

    Models with 'listings' metadata map to the auto-generated share for that listing
    (listing 'my_listing' -> share 'my_listing_share').

    The desired set is always derived from the whole graph, not just the nodes that ran,
    so that a selective run does not mistake unselected models for deletions. Each grant
    carries the unique_ids of the nodes that requested it so callers can hold back
    grants whose models did not succeed.
#}
{% macro get_desired_grants(share_config) %}
  {% if not execute %}
    {{ return({}) }}
  {% endif %}

  {% set desired_grants_by_share = {} %}
  {% for share_name in share_config.keys() %}
    {% do desired_grants_by_share.update({share_name: {}}) %}
  {% endfor %}

  {% for node in graph.nodes.values() %}
    {% if node.resource_type in ['model', 'snapshot'] %}
      {% set model_shares = node.meta.get('shares', []) or [] %}
      {% set model_listings = node.meta.get('listings', []) or [] %}

      {# Convert listings to auto-generated share names #}
      {% set listing_shares = [] %}
      {% for listing_name in model_listings %}
        {% do listing_shares.append(listing_name ~ '_share') %}
      {% endfor %}

      {% set all_shares = model_shares + listing_shares %}

      {% if all_shares %}
        {% set relation = api.Relation.create(
          database=node.database,
          schema=node.schema,
          identifier=node.alias or node.name
        ) %}

        {% set fqn = relation.render() %}
        {% set database_name = node.database %}
        {% set schema_fqn = database_name ~ '.' ~ node.schema %}

        {# Determine object type based on materialization #}
        {% set materialization = node.config.materialized %}
        {% set object_type = 'VIEW' if materialization == 'view' else 'TABLE' %}

        {% for share_name in all_shares %}
          {% if share_name in share_config.keys() %}
            {% set grants = desired_grants_by_share[share_name] %}
            {% do dbt_share_flake.add_desired_grant(grants, database_name, 'USAGE', 'DATABASE', node.unique_id) %}
            {% do dbt_share_flake.add_desired_grant(grants, schema_fqn, 'USAGE', 'SCHEMA', node.unique_id) %}
            {% do dbt_share_flake.add_desired_grant(grants, fqn, 'SELECT', object_type, node.unique_id) %}
          {% else %}
            {{ exceptions.warn("dbt-share-flake: share '" ~ share_name ~ "' is referenced by model '" ~ node.name ~ "' but is not defined in the snowflake_shares variable") }}
          {% endif %}
        {% endfor %}
      {% endif %}
    {% endif %}
  {% endfor %}

  {{ return(desired_grants_by_share) }}
{% endmacro %}
