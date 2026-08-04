{#
  Collects unique_ids of nodes that did not succeed in the current run.

  Args:
    None - reads the on-run-end `results` context variable if present

  Returns:
    list: unique_ids of nodes whose results were not successful

  Description:
    The on-run-end hook fires whether or not the run succeeded. A model that errored
    may have no relation at all, so granting on it fails and takes the whole hook
    down with it. A failing test means the data is suspect and sharing changes should
    wait. Either way we want to know which nodes to hold back.

    `results` is only in scope for on-run-end hooks, so its absence is treated as
    "nothing to report" rather than an error. Statuses are compared as lowercase
    strings because dbt models them as enums.
#}
{% macro get_blocked_node_ids() %}
  {% set blocked = [] %}

  {% if results is defined and results %}
    {% set successful_statuses = ['success', 'pass', 'warn'] %}
    {% for result in results %}
      {% set status = (result.status | string) | lower %}
      {% if status not in successful_statuses %}
        {% set node = result.node | default(none, true) %}
        {% set unique_id = (node.unique_id | default('', true)) if node else '' %}
        {% if unique_id %}
          {% do blocked.append(unique_id) %}
        {% endif %}
      {% endif %}
    {% endfor %}
  {% endif %}

  {{ return(blocked) }}
{% endmacro %}
