{#
  Validates a Snowflake account identifier.

  Args:
    account (str): Account identifier to validate

  Returns:
    str: The account identifier, unchanged, if it is valid

  Description:
    Account identifiers appear both in ALTER SHARE statements and in listing
    manifests. They are more permissive than plain identifiers because the
    organisation-qualified form (MYORG.MY_ACCOUNT) contains a dot, and organisation
    and account names may contain hyphens. Anything outside that character set is
    rejected rather than escaped.
#}
{% macro validate_account(account) %}
  {% set value = account | string %}

  {% if modules.re.match('^[A-Za-z0-9][A-Za-z0-9_.-]*$', value) is none %}
    {{ exceptions.raise_compiler_error(
      "dbt-share-flake: invalid Snowflake account identifier '" ~ value ~ "'. "
      ~ "Expected something like 'ABC12345' or 'MYORG.MY_ACCOUNT'."
    ) }}
  {% endif %}

  {{ return(value) }}
{% endmacro %}
