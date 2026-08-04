{#
  Manages grants to Snowflake shares by comparing desired vs existing grants.

  Args:
    share_config (dict): Dictionary mapping share names to their settings

  Returns:
    str: Empty string, so the macro is safe to call from inside a hook

  Description:
    Retained for backwards compatibility. Grant management is now planned across all
    shares at once so that dry-run and the revocation guards can see the whole picture,
    so this delegates to process_shares.
#}
{% macro grant_to_shares(share_config) %}
  {% do dbt_share_flake.process_shares(shares_config=share_config) %}
  {{ return('') }}
{% endmacro %}
