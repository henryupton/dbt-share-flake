{#
  Generates a SQL CREATE SHARE statement.

  Args:
    share_name (str): Name of the share to create

  Returns:
    str: SQL CREATE SHARE statement

  Description:
    Creates a SQL statement to create a new Snowflake share.
    Uses IF NOT EXISTS to avoid errors if the share already exists.
#}
{% macro get_create_share_sql(share_name) %}
  {% set create_sql %}
    CREATE SHARE IF NOT EXISTS {{ share_name }}
  {% endset %}
  {{ return(create_sql) }}
{% endmacro %}
