{#
  Creates a case-insensitive grant key for comparing grants.

  Args:
    *varargs: Variable arguments to join (object, privilege, type)

  Returns:
    str: Lowercased grant key joined with pipe separators

  Description:
    Takes variable arguments (typically object name, privilege, and object type)
    and creates a normalized key for grant comparison. All values are lowercased
    and joined with '|' to ensure case-insensitive matching.
#}
{% macro make_grant_key() %}
  {% set args = varargs %}
  {{ return((args | join('|')) | lower) }}
{% endmacro %}
