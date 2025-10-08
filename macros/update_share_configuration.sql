{#
  Updates share configuration (accounts and share_restrictions).

  Args:
    share_name (str): Name of the share to update
    desired_config (dict): Desired configuration with 'accounts' and 'share_restrictions'
    existing_config (dict): Current configuration from get_share_configuration

  Returns:
    None - Executes ALTER SHARE statements

  Description:
    Compares desired and existing configuration to determine changes:
    - Adds new accounts to the share (single ALTER statement)
    - Removes accounts no longer in desired config (single ALTER statement)
    - Updates share_restrictions setting if it has changed
#}
{% macro update_share_configuration(share_name, desired_config, existing_config) %}
  {% if execute %}
    {% set desired_accounts = desired_config.get('accounts', []) %}
    {% set existing_accounts = existing_config.get('accounts', []) %}
    {% set desired_restrictions = desired_config.get('share_restrictions', false) %}
    {% set existing_restrictions = existing_config.get('share_restrictions', false) %}

    {# Determine accounts to add and remove #}
    {% set accounts_to_add = [] %}
    {% set accounts_to_remove = [] %}

    {% for account in desired_accounts %}
      {% if account not in existing_accounts %}
        {% do accounts_to_add.append(account) %}
      {% endif %}
    {% endfor %}

    {% for account in existing_accounts %}
      {% if account not in desired_accounts %}
        {% do accounts_to_remove.append(account) %}
      {% endif %}
    {% endfor %}

    {# Add accounts in a single statement #}
    {% if accounts_to_add %}
      {% set accounts_list = accounts_to_add | join(', ') %}
      {% set alter_sql %}
        ALTER SHARE {{ share_name }} ADD ACCOUNTS = {{ accounts_list }}
      {% endset %}
      {{ log("Adding accounts " ~ accounts_list ~ " to share " ~ share_name, info=True) }}
      {% do run_query(alter_sql) %}
    {% endif %}

    {# Remove accounts in a single statement #}
    {% if accounts_to_remove %}
      {% set accounts_list = accounts_to_remove | join(', ') %}
      {% set alter_sql %}
        ALTER SHARE {{ share_name }} REMOVE ACCOUNTS = {{ accounts_list }}
      {% endset %}
      {{ log("Removing accounts " ~ accounts_list ~ " from share " ~ share_name, info=True) }}
      {% do run_query(alter_sql) %}
    {% endif %}

    {# Update share restrictions if different #}
    {% if desired_restrictions != existing_restrictions %}
      {% set alter_sql %}
        ALTER SHARE {{ share_name }} SET SHARE_RESTRICTIONS = {{ desired_restrictions | upper }}
      {% endset %}
      {{ log("Setting share_restrictions to " ~ desired_restrictions ~ " for share " ~ share_name, info=True) }}
      {% do run_query(alter_sql) %}
    {% endif %}
  {% endif %}
{% endmacro %}
