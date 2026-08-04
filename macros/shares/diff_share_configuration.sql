{#
  Diffs desired share configuration against what Snowflake currently reports.

  Args:
    desired_config (dict): Share settings from configuration ('accounts', 'share_restrictions')
    existing_config (dict): Current settings from get_share_configuration

  Returns:
    dict: {
      'accounts_to_add': list,
      'accounts_to_remove': list,
      'share_restrictions': bool,
      'restrictions_changed': bool
    }

  Description:
    Pure comparison with no side effects, so the plan can be shown before anything is
    executed. Account identifiers are validated here rather than at apply time so that
    a bad identifier fails before any DDL runs.

    Comparison is case-insensitive because Snowflake reports account identifiers in
    upper case regardless of how they were written in configuration.
#}
{% macro diff_share_configuration(desired_config, existing_config) %}
  {% set desired_accounts = desired_config.get('accounts', []) or [] %}
  {% set existing_accounts = existing_config.get('accounts', []) or [] %}
  {% set desired_restrictions = desired_config.get('share_restrictions', false) %}
  {% set existing_restrictions = existing_config.get('share_restrictions', false) %}

  {% set desired_normalized = [] %}
  {% for account in desired_accounts %}
    {% do desired_normalized.append(dbt_share_flake.validate_account(account) | upper) %}
  {% endfor %}

  {% set existing_normalized = [] %}
  {% for account in existing_accounts %}
    {% do existing_normalized.append(account | string | upper) %}
  {% endfor %}

  {% set accounts_to_add = [] %}
  {% for account in desired_accounts %}
    {% if (account | string | upper) not in existing_normalized %}
      {% do accounts_to_add.append(account) %}
    {% endif %}
  {% endfor %}

  {% set accounts_to_remove = [] %}
  {% for account in existing_accounts %}
    {% if (account | string | upper) not in desired_normalized %}
      {% do accounts_to_remove.append(account) %}
    {% endif %}
  {% endfor %}

  {{ return({
    'accounts_to_add': accounts_to_add,
    'accounts_to_remove': accounts_to_remove,
    'share_restrictions': desired_restrictions,
    'restrictions_changed': desired_restrictions != existing_restrictions
  }) }}
{% endmacro %}
