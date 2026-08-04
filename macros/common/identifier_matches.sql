{#
  Compares an identifier returned by Snowflake against an expected name.

  Args:
    candidate (str): Name as returned by SHOW (may be qualified, e.g. ORG.ACCOUNT.SHARE)
    expected (str): Unqualified name we are looking for

  Returns:
    bool: True if the final identifier segments match

  Description:
    SHOW SHARES reports outbound shares with an organisation- and account-qualified
    name, while configuration uses the bare share name. Comparison is done on the
    final dot-separated segment, case-insensitively and ignoring quoting, so that
    'MYORG.MYACCT.PARTNER_SHARE' matches 'partner_share'.
#}
{% macro identifier_matches(candidate, expected) %}
  {% set left = (candidate | string | replace('"', '')).split('.') | last | trim | lower %}
  {% set right = (expected | string | replace('"', '')).split('.') | last | trim | lower %}
  {{ return(left == right and left != '') }}
{% endmacro %}
