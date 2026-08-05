{#
  Records a desired grant, tracking which nodes asked for it.

  Args:
    grants (dict): Grant map to mutate, keyed by grant_key
    object_name (str): Object the privilege applies to
    privilege (str): Privilege to grant
    object_type (str): Object type ('DATABASE', 'SCHEMA', 'TABLE', 'VIEW')
    node_id (str): unique_id of the node that requires this grant

  Returns:
    None - mutates the supplied dict

  Description:
    Database and schema grants are shared by every model in that schema, so a grant
    key can be requested by many nodes. Recording all of them ('provenance') is what
    lets a failed model hold back only the grants that nothing else needs: if one model
    in a schema fails but its neighbour succeeded, the schema still needs USAGE.
#}
{% macro add_desired_grant(grants, object_name, privilege, object_type, node_id) %}
  {% set grant_key = dbt_share_flake.make_grant_key(object_name, privilege, object_type) %}
  {% set existing = grants.get(grant_key) %}

  {% if existing %}
    {% if node_id not in existing['nodes'] %}
      {% do existing['nodes'].append(node_id) %}
    {% endif %}
  {% else %}
    {% do grants.update({
      grant_key: {
        'object': object_name,
        'privilege': privilege,
        'type': object_type,
        'nodes': [node_id]
      }
    }) %}
  {% endif %}
{% endmacro %}
