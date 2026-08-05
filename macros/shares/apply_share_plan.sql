{#
  Executes a share plan.

  Args:
    plan (dict): Plan from build_share_plan
    dry_run (bool): When true, nothing is executed

  Returns:
    str: Empty string, so the macro is safe to call from inside a hook

  Description:
    Applies each share in turn: create the share, revoke what is no longer wanted,
    grant what is missing, then reconcile accounts. Accounts come last because a share
    with no objects in it cannot have accounts added.

    Revocations run before grants so that an object moving between shares does not
    briefly hold both. Ordering within each list is set by order_grants: containers
    before contents when granting, and the reverse when revoking.
#}
{% macro apply_share_plan(plan, dry_run=false) %}
  {% if not execute %}
    {{ return('') }}
  {% endif %}

  {% if dry_run %}
    {{ return('') }}
  {% endif %}

  {% for share_name, share_plan in plan.items() %}
    {% if share_plan['to_create'] %}
      {{ log("dbt-share-flake: creating share " ~ share_name, info=True) }}
      {% do run_query(dbt_share_flake.get_create_share_sql(share_name)) %}
    {% endif %}

    {% for grant in share_plan['to_revoke'] %}
      {% set revoke_sql = dbt_share_flake.get_revoke_sql(grant['object'], share_name, grant['privilege'], grant['type']) %}
      {{ log("dbt-share-flake: revoking " ~ (grant['privilege'] | lower) ~ " on " ~ (grant['type'] | lower) ~ " " ~ (grant['object'] | lower) ~ " from share " ~ share_name, info=True) }}
      {% do run_query(revoke_sql) %}
    {% endfor %}

    {% for grant in share_plan['to_add'] %}
      {% set grant_sql = dbt_share_flake.get_grant_sql(grant['object'], share_name, grant['privilege'], grant['type']) %}
      {{ log("dbt-share-flake: granting " ~ (grant['privilege'] | lower) ~ " on " ~ (grant['type'] | lower) ~ " " ~ (grant['object'] | lower) ~ " to share " ~ share_name, info=True) }}
      {% do run_query(grant_sql) %}
    {% endfor %}

    {% set config_diff = share_plan['config_diff'] %}
    {% if config_diff is not none %}
      {% do dbt_share_flake.update_share_configuration(share_name, {}, {}, dry_run=false, config_diff=config_diff) %}
    {% endif %}
  {% endfor %}

  {{ return('') }}
{% endmacro %}
