{#
  Compares desired grants with existing grants to find differences.

  Args:
    share_config (dict): Dictionary mapping share names to their settings
    desired_grants_by_share (dict): Nested dict of desired grants by share

  Returns:
    dict: Dictionary with two keys:
          - to_add: Grants that need to be created
          - to_revoke: Grants that need to be removed

  Description:
    For each share, retrieves existing grants and compares grant keys.
    Identifies grants to add (in desired but not existing) and
    grants to revoke (in existing but not desired).
#}
{% macro compare_grants(share_config, desired_grants_by_share) %}
  {% if execute %}
    {# Compare existing vs desired grants for each share #}
    {% set grants_to_add = {} %}
    {% set grants_to_revoke = {} %}

    {% for share_name in share_config.keys() %}
      {% set existing_grants = get_existing_grants(share_name) %}
      {% set desired_grants = desired_grants_by_share.get(share_name, {}) %}

      {# Find grants to revoke (in existing but not in desired) #}
      {% set revoke_list = [] %}
      {% for grant_key, grant_info in existing_grants.items() %}
        {% if grant_key not in desired_grants.keys() %}
          {% do revoke_list.append(grant_info) %}
        {% endif %}
      {% endfor %}

      {% if revoke_list %}
        {% do grants_to_revoke.update({share_name: revoke_list}) %}
      {% endif %}

      {# Find grants to add (in desired but not in existing) #}
      {% set add_list = [] %}
      {% for grant_key, grant_info in desired_grants.items() %}
        {% if grant_key not in existing_grants.keys() %}
          {% do add_list.append(grant_info) %}
        {% endif %}
      {% endfor %}

      {% if add_list %}
        {% do grants_to_add.update({share_name: add_list}) %}
      {% endif %}
    {% endfor %}

    {{ return({
      'to_add': grants_to_add,
      'to_revoke': grants_to_revoke
    }) }}
  {% endif %}

  {{ return({}) }}
{% endmacro %}
