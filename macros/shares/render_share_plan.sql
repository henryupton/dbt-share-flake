{#
  Logs a human-readable summary of a share plan.

  Args:
    plan (dict): Plan from build_share_plan
    dry_run (bool): Whether this plan will be executed
    revoke_reason (str, optional): Why revocations were suppressed, if they were

  Returns:
    str: Empty string, so the macro is safe to call from inside a hook

  Description:
    Printed before anything is executed, on every run rather than only in dry-run mode.
    Access changes are exactly the kind of thing worth having in the run log after the
    fact, and seeing the plan before the guards fire is what makes a threshold breach
    diagnosable rather than just annoying.
#}
{% macro render_share_plan(plan, dry_run=false, revoke_reason=none) %}
  {% set lines = [] %}
  {% set totals = namespace(add=0, revoke=0, suppressed=0, held=0) %}

  {% for share_name, share_plan in plan.items() %}
    {% set share_lines = [] %}
    {% set config_diff = share_plan['config_diff'] %}
    {% set accounts_add = config_diff['accounts_to_add'] if config_diff else [] %}
    {% set accounts_remove = config_diff['accounts_to_remove'] if config_diff else [] %}

    {% if share_plan['to_create'] %}
      {% do share_lines.append("    + create share") %}
    {% endif %}

    {% for grant in share_plan['to_add'] %}
      {% do share_lines.append("    + grant  " ~ (grant['privilege'] | lower).ljust(6) ~ " on " ~ (grant['type'] | lower).ljust(8) ~ " " ~ (grant['object'] | lower)) %}
    {% endfor %}

    {% for grant in share_plan['to_revoke'] %}
      {% do share_lines.append("    - revoke " ~ (grant['privilege'] | lower).ljust(6) ~ " on " ~ (grant['type'] | lower).ljust(8) ~ " " ~ (grant['object'] | lower)) %}
    {% endfor %}

    {% for grant in share_plan['revokes_suppressed'] %}
      {% do share_lines.append("    ! skipped revoke of " ~ (grant['privilege'] | lower) ~ " on " ~ (grant['type'] | lower) ~ " " ~ (grant['object'] | lower)) %}
    {% endfor %}

    {% for grant in share_plan['held_back'] %}
      {% do share_lines.append("    ! held back grant " ~ (grant['privilege'] | lower) ~ " on " ~ (grant['type'] | lower) ~ " " ~ (grant['object'] | lower) ~ " (requesting model did not succeed)") %}
    {% endfor %}

    {% if accounts_add %}
      {% do share_lines.append("    ~ add accounts " ~ accounts_add | join(', ') ~ " (share_restrictions = " ~ ('TRUE' if config_diff['share_restrictions'] else 'FALSE') ~ ")") %}
    {% endif %}
    {% if accounts_remove %}
      {% do share_lines.append("    ~ remove accounts " ~ accounts_remove | join(', ')) %}
    {% endif %}

    {% if share_lines %}
      {% do lines.append("  share " ~ share_name) %}
      {% for line in share_lines %}
        {% do lines.append(line) %}
      {% endfor %}
    {% endif %}

    {% set totals.add = totals.add + (share_plan['to_add'] | length) %}
    {% set totals.revoke = totals.revoke + (share_plan['to_revoke'] | length) %}
    {% set totals.suppressed = totals.suppressed + (share_plan['revokes_suppressed'] | length) %}
    {% set totals.held = totals.held + (share_plan['held_back'] | length) %}
  {% endfor %}

  {% if not lines %}
    {{ log("dbt-share-flake: shares already match configuration, nothing to do", info=True) }}
    {{ return('') }}
  {% endif %}

  {% set summary = totals.add ~ " to grant, " ~ totals.revoke ~ " to revoke" %}
  {% if totals.suppressed > 0 %}
    {% set summary = summary ~ ", " ~ totals.suppressed ~ " revoke(s) skipped" %}
  {% endif %}
  {% if totals.held > 0 %}
    {% set summary = summary ~ ", " ~ totals.held ~ " grant(s) held back" %}
  {% endif %}

  {{ log("dbt-share-flake: " ~ ("DRY RUN, nothing will be executed. " if dry_run else "") ~ summary, info=True) }}

  {% if revoke_reason %}
    {{ log("dbt-share-flake: revocations skipped because " ~ revoke_reason, info=True) }}
  {% endif %}

  {% for line in lines %}
    {{ log("dbt-share-flake: " ~ line, info=True) }}
  {% endfor %}

  {{ return('') }}
{% endmacro %}
