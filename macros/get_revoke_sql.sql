{#
  Generates a SQL REVOKE statement for a share.

  Args:
    object_name (str): Fully qualified name of the object to revoke from
    share_name (str): Name of the share to revoke from
    privilege (str): Privilege to revoke (e.g., 'USAGE', 'SELECT')
    object_type (str): Type of object (e.g., 'DATABASE', 'SCHEMA', 'TABLE', 'VIEW')

  Returns:
    str: SQL REVOKE statement

  Description:
    Creates a SQL statement to revoke a specific privilege on an object from a share.
#}
{% macro get_revoke_sql(object_name, share_name, privilege, object_type) %}
  {% set revoke_sql %}
    REVOKE {{ privilege }} ON {{ object_type }} {{ object_name }} FROM SHARE {{ share_name }}
  {% endset %}
  {{ return(revoke_sql) }}
{% endmacro %}
