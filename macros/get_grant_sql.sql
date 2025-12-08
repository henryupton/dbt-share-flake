{#
  Generates a SQL GRANT statement for a share.

  Args:
    object_name (str): Fully qualified name of the object to grant
    share_name (str): Name of the share to grant to
    privilege (str): Privilege to grant (e.g., 'USAGE', 'SELECT')
    object_type (str): Type of object (e.g., 'DATABASE', 'SCHEMA', 'TABLE', 'VIEW')

  Returns:
    str: SQL GRANT statement

  Description:
    Creates a SQL statement to grant a specific privilege on an object to a share.
#}
{% macro get_grant_sql(object_name, share_name, privilege, object_type) %}
  {# Normalize object type for grant syntax (e.g., ICEBERG TABLE -> TABLE) #}
  {% set normalized_type = dbt_share_flake.normalize_object_type(object_type) %}
  {% set grant_sql %}
    GRANT {{ privilege }} ON {{ normalized_type }} {{ object_name }} TO SHARE {{ share_name }}
  {% endset %}
  {{ return(grant_sql) }}
{% endmacro %}
