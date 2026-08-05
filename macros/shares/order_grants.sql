{#
  Orders grants so that dependencies are satisfied.

  Args:
    grants (list): List of grant_info dicts
    reverse (bool): When true, order for revocation instead of granting

  Returns:
    list: The same grants, ordered

  Description:
    Snowflake requires the containing objects to be added to a share before the objects
    inside them: USAGE on the database, then USAGE on the schema, then SELECT on the
    relation. Revocation has to unwind in the opposite order.

    Previously this ordering was an accident of dict insertion order. Making it
    explicit means a change to how the desired set is built cannot silently produce
    grants that fail.
#}
{% macro order_grants(grants, reverse=false) %}
  {% set precedence = ['DATABASE', 'SCHEMA'] %}
  {% set ordered = [] %}

  {% for object_type in precedence %}
    {% for grant in grants %}
      {% if (grant['type'] | upper) == object_type %}
        {% do ordered.append(grant) %}
      {% endif %}
    {% endfor %}
  {% endfor %}

  {% for grant in grants %}
    {% if (grant['type'] | upper) not in precedence %}
      {% do ordered.append(grant) %}
    {% endif %}
  {% endfor %}

  {% if reverse %}
    {{ return(ordered | reverse | list) }}
  {% endif %}

  {{ return(ordered) }}
{% endmacro %}
