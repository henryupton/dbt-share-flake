{#
  Share module entrypoint for Snowflake share grant management.

  Args:
    shares_config (dict, optional): Share configuration. Defaults to var('snowflake_shares', {})

  Returns:
    str: Empty string, so the macro is safe to call from inside a hook

  Description:
    Plans first, guards second, applies last:
    1. Checks the run gate (enabled, command, target allowlist)
    2. Optionally checks for required privileges
    3. Builds the complete plan for every share in one pass
    4. Decides whether revocation is safe, and aborts if it exceeds the threshold
    5. Logs the plan
    6. Applies it, unless this is a dry run

    The guards exist because revocation is the one operation here that can break a live
    consumer. Desired state comes from the dbt graph, so anything that narrows the graph
    without narrowing the intent (a selector, a partially failed run, a subsetted
    project) makes still-wanted grants look like deletions.
#}
{% macro process_shares(shares_config=none) %}
  {% if not dbt_share_flake.should_run() %}
    {{ return('') }}
  {% endif %}

  {% set share_config = shares_config if shares_config is not none else var('snowflake_shares', {}) %}

  {% if not share_config %}
    {{ log("dbt-share-flake: no shares configured in the snowflake_shares variable", info=True) }}
    {{ return('') }}
  {% endif %}

  {% if var('snowflake_shares_check_privileges', true) %}
    {% set required_privileges = [
        'CREATE SHARE',
        'IMPORT SHARE',
        'MANAGE GRANTS',
        'MANAGE SHARE TARGET'
    ] %}
    {% do dbt_share_flake.check_required_privileges(required_privileges) %}
  {% endif %}

  {% set dry_run = var('snowflake_sharing_dry_run', false) %}
  {% set blocked_node_ids = dbt_share_flake.get_blocked_node_ids() %}
  {% set plan = dbt_share_flake.build_share_plan(share_config, blocked_node_ids) %}

  {# Decide whether revocation is safe for this invocation #}
  {% set revoke_reason = none %}
  {% if not var('snowflake_sharing_allow_revoke', true) %}
    {% set revoke_reason = 'snowflake_sharing_allow_revoke is false' %}
  {% elif blocked_node_ids and not var('snowflake_sharing_revoke_after_failure', false) %}
    {% set revoke_reason = blocked_node_ids | length ~ ' node(s) did not succeed in this run (set snowflake_sharing_revoke_after_failure to override)' %}
  {% elif dbt_share_flake.is_partial_selection() and not var('snowflake_sharing_revoke_on_partial_selection', false) %}
    {% set revoke_reason = 'this run used --select, --exclude or --selector (set snowflake_sharing_revoke_on_partial_selection to override)' %}
  {% endif %}

  {% if revoke_reason %}
    {% for share_name, share_plan in plan.items() %}
      {% do share_plan.update({
        'revokes_suppressed': share_plan['to_revoke'],
        'to_revoke': []
      }) %}
    {% endfor %}
  {% endif %}

  {% do dbt_share_flake.render_share_plan(plan, dry_run=dry_run, revoke_reason=revoke_reason) %}

  {# Threshold guard: refuse to mass-revoke without an explicit decision #}
  {% set max_revokes = var('snowflake_sharing_max_revokes', 20) %}
  {% set revoke_count = dbt_share_flake.count_plan_revokes(plan) %}
  {% if max_revokes is not none and revoke_count > max_revokes %}
    {% if dry_run %}
      {{ log(
        "dbt-share-flake: this plan would revoke " ~ revoke_count ~ " grants, above the "
        ~ "snowflake_sharing_max_revokes limit of " ~ max_revokes ~ ". A real run would abort.", info=True
      ) }}
    {% else %}
      {{ exceptions.raise_compiler_error(
        "dbt-share-flake: refusing to revoke " ~ revoke_count ~ " grants, which is above the "
        ~ "snowflake_sharing_max_revokes limit of " ~ max_revokes ~ ". Nothing has been changed. "
        ~ "Review the plan logged above, then either raise snowflake_sharing_max_revokes or set "
        ~ "snowflake_sharing_allow_revoke to false to apply the grants without the revocations."
      ) }}
    {% endif %}
  {% endif %}

  {% do dbt_share_flake.apply_share_plan(plan, dry_run=dry_run) %}

  {% if not dry_run %}
    {{ log("dbt-share-flake: share management complete", info=True) }}
  {% endif %}

  {{ return('') }}
{% endmacro %}
