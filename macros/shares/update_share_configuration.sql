{#
  Updates share configuration (accounts and share_restrictions).

  Args:
    share_name (str): Name of the share to update
    desired_config (dict): Desired configuration with 'accounts' and 'share_restrictions'
    existing_config (dict): Current configuration from get_share_configuration
    dry_run (bool): When true, log the statements without executing them
    config_diff (dict, optional): Pre-computed diff from diff_share_configuration

  Returns:
    None - Executes ALTER SHARE statements

  Description:
    Applies the account changes from diff_share_configuration.

    SHARE_RESTRICTIONS is not an independently settable share property: Snowflake only
    accepts it as a modifier on ADD ACCOUNTS, and it has to be repeated every time a
    non-Business-Critical consumer account is added. It is therefore emitted as part of
    the ADD ACCOUNTS statement, and a request to change it in isolation warns rather
    than issuing DDL that Snowflake would reject.
#}
{% macro update_share_configuration(share_name, desired_config, existing_config, dry_run=false, config_diff=none) %}
  {% if not execute %}
    {{ return('') }}
  {% endif %}

  {% set share = dbt_share_flake.validate_identifier(share_name, 'share name') %}
  {% set diff = config_diff if config_diff is not none else dbt_share_flake.diff_share_configuration(desired_config, existing_config) %}

  {% set accounts_to_add = diff['accounts_to_add'] %}
  {% set accounts_to_remove = diff['accounts_to_remove'] %}
  {% set share_restrictions = diff['share_restrictions'] %}

  {% if accounts_to_add %}
    {% set accounts_list = accounts_to_add | join(', ') %}
    {% set alter_sql %}
      ALTER SHARE {{ share }} ADD ACCOUNTS = {{ accounts_list }} SHARE_RESTRICTIONS = {{ 'TRUE' if share_restrictions else 'FALSE' }}
    {% endset %}
    {{ log("dbt-share-flake: " ~ ("[dry run] " if dry_run else "") ~ "adding accounts " ~ accounts_list ~ " to share " ~ share, info=True) }}
    {% if not dry_run %}
      {% do run_query(alter_sql) %}
    {% endif %}
  {% endif %}

  {% if accounts_to_remove %}
    {% set accounts_list = accounts_to_remove | join(', ') %}
    {% set alter_sql %}
      ALTER SHARE {{ share }} REMOVE ACCOUNTS = {{ accounts_list }}
    {% endset %}
    {{ log("dbt-share-flake: " ~ ("[dry run] " if dry_run else "") ~ "removing accounts " ~ accounts_list ~ " from share " ~ share, info=True) }}
    {% if not dry_run %}
      {% do run_query(alter_sql) %}
    {% endif %}
  {% endif %}

  {% if diff['restrictions_changed'] and not accounts_to_add %}
    {{ exceptions.warn(
      "dbt-share-flake: share_restrictions for share '" ~ share ~ "' differs from Snowflake, "
      ~ "but Snowflake only accepts SHARE_RESTRICTIONS alongside ADD ACCOUNTS. "
      ~ "It will be applied the next time an account is added to this share."
    ) }}
  {% endif %}
{% endmacro %}
