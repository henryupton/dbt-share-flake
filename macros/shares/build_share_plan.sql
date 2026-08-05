{#
  Builds the full set of changes required across every configured share.

  Args:
    share_config (dict): Dictionary mapping share names to their settings
    blocked_node_ids (list): unique_ids of nodes that did not succeed this run

  Returns:
    dict: {share_name: {
             'exists': bool,
             'to_create': bool,
             'to_add': list,
             'to_revoke': list,
             'revokes_suppressed': list,
             'held_back': list,
             'config_diff': dict or none
           }}

  Description:
    Computes everything that would change before anything is executed. Separating the
    plan from the apply is what makes dry-run, the revoke threshold guard, and a
    readable summary possible, and it means the graph is walked once for all shares
    rather than once per share.

    Grants whose every requesting node failed or was skipped this run are moved to
    'held_back' rather than 'to_add', because the relation may not exist. Grants shared
    with a node that did succeed are still applied.

    Share configuration is only diffed when it would actually be applied: always for a
    share this run would create, and otherwise only when snowflake_shares_alter_share
    is enabled. That avoids a DESCRIBE SHARE per share on every run.
#}
{% macro build_share_plan(share_config, blocked_node_ids=[]) %}
  {% if not execute %}
    {{ return({}) }}
  {% endif %}

  {% set alter_share = var('snowflake_shares_alter_share', false) %}
  {% set desired_by_share = dbt_share_flake.get_desired_grants(share_config) %}
  {% set plan = {} %}

  {% for share_name, raw_settings in share_config.items() %}
    {% set share_settings = raw_settings or {} %}
    {% set exists = dbt_share_flake.share_exists(share_name) %}
    {% set existing_grants = dbt_share_flake.get_existing_grants(share_name) if exists else {} %}
    {% set desired_grants = desired_by_share.get(share_name, {}) %}

    {# Grants that are desired but not yet present #}
    {% set to_add = [] %}
    {% set held_back = [] %}
    {% for grant_key, grant_info in desired_grants.items() %}
      {% if grant_key not in existing_grants %}
        {% set requesting_nodes = grant_info.get('nodes', []) %}
        {% set live_nodes = [] %}
        {% for node_id in requesting_nodes %}
          {% if node_id not in blocked_node_ids %}
            {% do live_nodes.append(node_id) %}
          {% endif %}
        {% endfor %}

        {% if requesting_nodes and not live_nodes %}
          {% do held_back.append(grant_info) %}
        {% else %}
          {% do to_add.append(grant_info) %}
        {% endif %}
      {% endif %}
    {% endfor %}

    {# Grants that exist but are no longer desired #}
    {% set to_revoke = [] %}
    {% for grant_key, grant_info in existing_grants.items() %}
      {% if grant_key not in desired_grants %}
        {% do to_revoke.append(grant_info) %}
      {% endif %}
    {% endfor %}

    {# Only diff share configuration when it would be applied #}
    {% set config_diff = none %}
    {% if not exists or alter_share %}
      {% set existing_config = dbt_share_flake.get_share_configuration(share_name) if exists else {'accounts': [], 'share_restrictions': false} %}
      {% set config_diff = dbt_share_flake.diff_share_configuration(share_settings, existing_config) %}
    {% endif %}

    {% do plan.update({
      share_name: {
        'exists': exists,
        'to_create': not exists,
        'to_add': dbt_share_flake.order_grants(to_add),
        'to_revoke': dbt_share_flake.order_grants(to_revoke, reverse=true),
        'revokes_suppressed': [],
        'held_back': held_back,
        'config_diff': config_diff
      }
    }) %}
  {% endfor %}

  {{ return(plan) }}
{% endmacro %}
