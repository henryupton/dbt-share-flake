{#
  Validates that a name is safe to interpolate into DDL as an unquoted identifier.

  Args:
    name (str): The identifier to validate
    kind (str): Human-readable description used in the error message

  Returns:
    str: The identifier, unchanged, if it is valid

  Description:
    Share, listing and role names are interpolated directly into DDL. Quoting them
    would change their case semantics (a quoted lowercase name is a different object
    to an unquoted one), so instead we fail closed on anything that is not a plain
    Snowflake identifier: a letter or underscore followed by letters, digits,
    underscores or dollar signs.

    This is the injection guard for every macro that builds DDL from configuration.
#}
{% macro validate_identifier(name, kind='identifier') %}
  {% set value = name | string %}

  {% if modules.re.match('^[A-Za-z_][A-Za-z0-9_$]*$', value) is none %}
    {{ exceptions.raise_compiler_error(
      "dbt-share-flake: invalid " ~ kind ~ " '" ~ value ~ "'. "
      ~ "Must start with a letter or underscore and contain only letters, digits, "
      ~ "underscores or dollar signs. Quoted or special-character names are not supported."
    ) }}
  {% endif %}

  {{ return(value) }}
{% endmacro %}
