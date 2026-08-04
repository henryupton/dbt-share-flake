{#
  Creates a comparable grant key from an object name, privilege and object type.

  Args:
    *varargs: Variable arguments to join (object, privilege, type)

  Returns:
    str: Normalized grant key joined with pipe separators

  Description:
    Desired grants and existing grants arrive in different shapes, and the key has to
    make them comparable:

    - Desired object names come from dbt's relation rendering, which honours the
      project's quoting config. With quoting enabled that produces
      '"ANALYTICS"."PUBLIC"."ORDERS"'.
    - Existing object names come from SHOW GRANTS TO SHARE, which always reports them
      unquoted as 'ANALYTICS.PUBLIC.ORDERS'.

    So each part is stripped of quotes, trimmed and lowercased before joining. Without
    the quote stripping, a project with `quoting: {identifier: true}` sees every grant as
    simultaneously missing and stale, and revokes then re-grants the same objects on
    every single run.

    The consequence of normalising case is that a deliberately quoted lowercase object
    ("orders") and an unquoted one (ORDERS) produce the same key, even though Snowflake
    treats them as different objects. SHOW GRANTS does not report which parts of a name
    were quoted, so telling them apart is not possible here.
#}
{% macro make_grant_key() %}
  {% set parts = [] %}
  {% for arg in varargs %}
    {% do parts.append((arg | string | replace('"', '') | trim) | lower) %}
  {% endfor %}
  {{ return(parts | join('|')) }}
{% endmacro %}
