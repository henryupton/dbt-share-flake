{#
  Normalizes object types for grant/revoke syntax.

  Args:
    object_type (str): Object type from Snowflake (e.g., 'TABLE', 'ICEBERG TABLE', 'DYNAMIC TABLE', 'VIEW')

  Returns:
    str: Normalized object type for use in GRANT/REVOKE statements

  Description:
    Snowflake's SHOW GRANTS returns specific table variants like 'ICEBERG TABLE' or 'DYNAMIC TABLE',
    but the GRANT/REVOKE syntax requires just 'TABLE' for all table types.
    This macro normalizes variant table types to 'TABLE' while preserving other types like 'VIEW'.
#}
{% macro normalize_object_type(object_type) %}
  {% set normalized = object_type | upper %}
  {% if 'TABLE' in normalized and normalized != 'TABLE' %}
    {% set normalized = 'TABLE' %}
  {% endif %}
  {{ return(normalized) }}
{% endmacro %}
