{#
  Escapes a free-text value for use as a YAML double-quoted scalar.

  Args:
    value (str): The value to escape
    field (str): Field name, used in the error message

  Returns:
    str: The escaped value, without surrounding quotes

  Description:
    Listing manifests are YAML embedded in a dollar-quoted SQL block. An unescaped
    double quote in a title or description produces invalid YAML, and a literal '$$'
    terminates the SQL block early, which would let configuration text execute as SQL.

    Backslashes and double quotes are escaped, and newlines and tabs are converted to
    YAML escape sequences so the value stays on one line. '$$' cannot be represented
    inside a dollar-quoted block at all, so it is rejected outright.
#}
{% macro escape_yaml_value(value, field='value') %}
  {% set raw = value | string %}

  {% if '$$' in raw %}
    {{ exceptions.raise_compiler_error(
      "dbt-share-flake: listing " ~ field ~ " may not contain '$$' because the listing "
      ~ "manifest is sent inside a dollar-quoted block. Offending value: " ~ raw
    ) }}
  {% endif %}

  {% set escaped = raw
    | replace('\\', '\\\\')
    | replace('"', '\\"')
    | replace('\r\n', '\\n')
    | replace('\n', '\\n')
    | replace('\r', '\\n')
    | replace('\t', '\\t')
  %}

  {{ return(escaped) }}
{% endmacro %}
