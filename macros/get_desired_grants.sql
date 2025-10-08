{#
  Extracts desired grants from the dbt graph based on model metadata.

  Args:
    share_config (dict): Dictionary mapping share names to their settings

  Returns:
    dict: Nested dictionary structure {share_name: {grant_key: grant_info}}
          where grant_info contains object, privilege, and type

  Description:
    Iterates through all models and snapshots in the dbt graph.
    For each model with a 'shares' metadata field:
    - Creates USAGE grants on the database
    - Creates USAGE grants on the schema
    - Creates SELECT grants on the table/view (based on materialization)
#}
{% macro get_desired_grants(share_config) %}
  {% if execute %}
    {# Build a mapping of grant_key to grant info, indexed by share #}
    {% set desired_grants_by_share = {} %}

    {# Initialize structure for each share #}
    {% for share_name in share_config.keys() %}
      {% do desired_grants_by_share.update({share_name: {}}) %}
    {% endfor %}

    {# Step 1: Iterate through all nodes to collect object grants #}
    {% for node in graph.nodes.values() %}
      {% if node.resource_type in ['model', 'snapshot'] %}
        {% set model_shares = node.meta.get('shares', []) %}

        {% if model_shares %}
          {% set relation = api.Relation.create(
            database=node.database,
            schema=node.schema,
            identifier=node.alias or node.name
          ) %}

          {% set fqn = relation.render() %}
          {% set database_name = node.database %}
          {% set schema_name = node.schema %}
          {% set schema_fqn = database_name ~ '.' ~ schema_name %}

          {% for share_name in model_shares %}
            {% if share_name in share_config.keys() %}
              {# Add database grant #}
              {% set db_grant_key = make_grant_key(database_name, 'USAGE', 'DATABASE') %}
              {% do desired_grants_by_share[share_name].update({
                db_grant_key: {'object': database_name, 'privilege': 'USAGE', 'type': 'DATABASE'}
              }) %}

              {# Add schema grant #}
              {% set schema_grant_key = make_grant_key(schema_fqn, 'USAGE', 'SCHEMA') %}
              {% do desired_grants_by_share[share_name].update({
                schema_grant_key: {'object': schema_fqn, 'privilege': 'USAGE', 'type': 'SCHEMA'}
              }) %}

              {# Add table/view grant - determine type based on materialization #}
              {% set materialization = node.config.materialized %}
              {% if materialization == 'view' %}
                {% set object_type = 'VIEW' %}
              {% else %}
                {% set object_type = 'TABLE' %}
              {% endif %}
              {% set object_grant_key = make_grant_key(fqn, 'SELECT', object_type) %}
              {% do desired_grants_by_share[share_name].update({
                object_grant_key: {'object': fqn, 'privilege': 'SELECT', 'type': object_type}
              }) %}
            {% else %}
              {{ exceptions.warn("Warning: Share '" ~ share_name ~ "' referenced in model '" ~ node.name ~ "' but not defined in snowflake_shares variable") }}
            {% endif %}
          {% endfor %}
        {% endif %}
      {% endif %}
    {% endfor %}

    {{ return(desired_grants_by_share) }}
  {% endif %}

  {{ return({}) }}
{% endmacro %}
