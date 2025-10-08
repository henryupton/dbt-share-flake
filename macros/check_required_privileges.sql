{#
  Checks if the current role has the required privileges.

  Args:
    required_privileges (list): List of privilege names to check for

  Returns:
    list: List of missing privileges (empty if all privileges are present)

  Description:
    Queries SHOW GRANTS TO ROLE to check if the current role has all
    required privileges. Issues warnings for any missing privileges.
    Filters the query to only check for the specific required privileges
    for better performance.
#}
{% macro check_required_privileges(required_privileges) %}
  {% if execute %}
    {# First, get the current role #}
    {% set role_query %}
      SELECT CURRENT_ROLE() as "current_role"
    {% endset %}

    {% set role_result = run_query(role_query) %}
    {% set current_role = role_result.columns[0].values()[0] %}

    {# Now show grants for that role #}
    {% set privilege_list = "'" ~ required_privileges | join("', '") ~ "'" %}
    {% set query %}
      SHOW GRANTS TO ROLE {{ current_role }} ->> SELECT "privilege" FROM $1 WHERE "privilege" IN ({{ privilege_list }})
    {% endset %}

    {% set results = run_query(query) %}
    {% set granted_privileges = [] %}

    {% for row in results %}
      {% set privilege = row['privilege'] %}
      {% do granted_privileges.append(privilege) %}
    {% endfor %}

    {# Check each required privilege #}
    {% set missing_privileges = [] %}
    {% for required_privilege in required_privileges %}
      {% if required_privilege not in granted_privileges %}
        {% do missing_privileges.append(required_privilege) %}
      {% endif %}
    {% endfor %}

    {# Warn if any privileges are missing #}
    {% if missing_privileges %}
      {% for privilege in missing_privileges %}
        {{ exceptions.warn("Current role does not have '" ~ privilege ~ "' privilege. This may cause undocumented behaviour.") }}
      {% endfor %}
    {% endif %}

    {{ return(missing_privileges) }}
  {% endif %}

  {{ return([]) }}
{% endmacro %}
