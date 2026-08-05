{#
  Counts the revocations a plan would perform.

  Args:
    plan (dict): Plan from build_share_plan

  Returns:
    int: Total number of revoke statements across all shares

  Description:
    Used by the threshold guard. Counted across the whole plan rather than per share so
    that a configuration mistake spread thinly over many shares still trips the guard.
#}
{% macro count_plan_revokes(plan) %}
  {% set total = namespace(value=0) %}
  {% for share_name, share_plan in plan.items() %}
    {% set total.value = total.value + (share_plan['to_revoke'] | length) %}
  {% endfor %}
  {{ return(total.value) }}
{% endmacro %}
