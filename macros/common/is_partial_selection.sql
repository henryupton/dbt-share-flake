{#
  Detects whether the current invocation selected a subset of the project.

  Args:
    None - inspects dbt's flags

  Returns:
    bool: True if --select, --exclude or --selector was used

  Description:
    Desired grants are derived from the whole dbt graph, so a partial run still
    computes the correct desired state. The danger is the opposite direction: if a
    selector also narrows the graph (state selection, a subsetted project, a
    mis-typed selector) then objects that are still meant to be shared look like
    removals and get revoked from live consumers.

    Revocation is therefore skipped for selective runs by default. Flags are read via
    the `attr` filter so that a flag missing on the current dbt version yields
    undefined rather than raising, and both upper and lower case spellings are tried.
#}
{% macro is_partial_selection() %}
  {% set selection_flags = ['SELECT', 'EXCLUDE', 'SELECTOR', 'select', 'exclude', 'selector'] %}

  {% for flag_name in selection_flags %}
    {% set value = flags | attr(flag_name) | default([], true) %}
    {% if value | length > 0 %}
      {{ return(true) }}
    {% endif %}
  {% endfor %}

  {{ return(false) }}
{% endmacro %}
