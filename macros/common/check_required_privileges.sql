{#
  Checks if the current role has the required privileges.

  Args:
    required_privileges (list): List of privilege names to check for

  Returns:
    list: List of missing privileges (empty if all privileges are present)

  Description:
    Queries SHOW GRANTS ON ACCOUNT, filtered to the current role, to check
    that it holds every required privilege. Issues warnings for any that are
    missing. Every privilege this package checks is account-level, and the
    account-scoped SHOW returns only account-level grants, so it stays fast
    regardless of how many object grants the role holds.
#}
{% macro check_required_privileges(required_privileges) %}
  {% if execute %}
    {# First, get the current role #}
    {% set role_query %}
      SELECT CURRENT_ROLE() as "current_role"
    {% endset %}

    {% set role_result = run_query(role_query) %}
    {% set current_role = role_result.columns[0].values()[0] %}

    {# Account-level grants only, filtered to the current role #}
    {% set privilege_list = "'" ~ required_privileges | join("', '") ~ "'" %}
    {% set query %}
      SHOW GRANTS ON ACCOUNT ->> SELECT "privilege" FROM $1 WHERE "grantee_name" = '{{ current_role }}' AND "privilege" IN ({{ privilege_list }})
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
