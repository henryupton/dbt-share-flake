{#
  Manages grants to Snowflake shares by comparing desired vs existing grants.

  Args:
    share_config (dict): Dictionary mapping share names to their settings

  Returns:
    None - Executes SQL to grant/revoke privileges

  Description:
    This macro orchestrates the grant management process:
    1. Gets desired grants from dbt graph based on model metadata
    2. Compares with existing grants on the share
    3. Revokes grants that are no longer needed
    4. Applies new grants that are missing
#}
{% macro grant_to_shares(share_config) %}
  {% if execute %}
    {% if share_config %}

      {# Step 1: Get desired grants from dbt graph #}
      {% set desired_grants = dbt_share_flake.get_desired_grants(share_config) %}

      {# Step 2: Compare with existing grants to find diffs #}
      {% set grant_diffs = dbt_share_flake.compare_grants(share_config, desired_grants) %}

      {# Step 3: Revoke outdated grants #}
      {% set total_revokes = grant_diffs['to_revoke'].values() | sum(start=[]) | length %}
      {% if total_revokes > 0 %}
        {% set revoke_counter = namespace(value=0) %}
        {% for share_name, revoke_list in grant_diffs['to_revoke'].items() %}
          {% for grant_info in revoke_list %}
            {% set revoke_counter.value = revoke_counter.value + 1 %}
            {% set revoke_sql = dbt_share_flake.get_revoke_sql(grant_info['object'], share_name, grant_info['privilege'], grant_info['type']) %}
            {{ log(revoke_counter.value ~ " of " ~ total_revokes ~ " START revoke " ~ grant_info['privilege'] | lower ~ " on " ~ grant_info['type'] | lower ~ " " ~ grant_info['object'] | lower ~ " from share " ~ share_name, info=True) }}
            {% do run_query(revoke_sql) %}
            {{ log(revoke_counter.value ~ " of " ~ total_revokes ~ " OK revoke " ~ grant_info['privilege'] | lower ~ " on " ~ grant_info['type'] | lower ~ " " ~ grant_info['object'] | lower ~ " from share " ~ share_name, info=True) }}
          {% endfor %}
        {% endfor %}
      {% endif %}

      {# Step 4: Apply grants that need to be added #}
      {% set total_grants = grant_diffs['to_add'].values() | sum(start=[]) | length %}
      {% if total_grants > 0 %}
        {% set grant_counter = namespace(value=0) %}
        {% for share_name, grants_to_add in grant_diffs['to_add'].items() %}
          {% for grant_info in grants_to_add %}
            {% set grant_counter.value = grant_counter.value + 1 %}
            {% set grant_sql = dbt_share_flake.get_grant_sql(grant_info['object'], share_name, grant_info['privilege'], grant_info['type']) %}
            {{ log(grant_counter.value ~ " of " ~ total_grants ~ " START grant " ~ grant_info['privilege'] | lower ~ " on " ~ grant_info['type'] | lower ~ " " ~ grant_info['object'] | lower ~ " to share " ~ share_name, info=True) }}
            {% do run_query(grant_sql) %}
            {{ log(grant_counter.value ~ " of " ~ total_grants ~ " OK grant " ~ grant_info['privilege'] | lower ~ " on " ~ grant_info['type'] | lower ~ " " ~ grant_info['object'] | lower ~ " to share " ~ share_name, info=True) }}
          {% endfor %}
        {% endfor %}
      {% else %}
        {{ log("No share grants to apply", info=True) }}
      {% endif %}
    {% else %}
      {{ log("No Snowflake shares configured in snowflake_shares variable", info=True) }}
    {% endif %}
  {% endif %}
{% endmacro %}
