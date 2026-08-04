{% macro verify_shares() %}
  {% set shares_to_check = ['test_share_1', 'test_share_2'] %}

  {% for share_name in shares_to_check %}
    {% set query %}
      SHOW SHARES LIKE '{{ share_name }}'
    {% endset %}

    {% set results = run_query(query) %}

    {% if results.rows | length == 0 %}
      {{ exceptions.raise_compiler_error("Share " ~ share_name ~ " does not exist!") }}
    {% else %}
      {{ log("✓ Share " ~ share_name ~ " exists", info=True) }}
    {% endif %}
  {% endfor %}

  {{ log("All shares verified successfully!", info=True) }}
{% endmacro %}

{% macro verify_grants() %}
  {% set expected_grants = {
    'test_share_1': ['SHARED_CUSTOMERS', 'SHARED_ORDERS'],
    'test_share_2': ['SHARED_ORDERS']
  } %}

  {% for share_name, expected_objects in expected_grants.items() %}
    {% set query %}
      SHOW GRANTS TO SHARE {{ share_name }}
    {% endset %}

    {% set results = run_query(query) %}
    {% set granted_objects = [] %}

    {% for row in results %}
      {% if row['granted_on'] in ['TABLE', 'VIEW'] %}
        {% set object_name = row['name'].split('.')[-1] %}
        {% do granted_objects.append(object_name) %}
      {% endif %}
    {% endfor %}

    {% for expected_obj in expected_objects %}
      {% if expected_obj not in granted_objects %}
        {{ exceptions.raise_compiler_error("Expected object " ~ expected_obj ~ " not granted to share " ~ share_name) }}
      {% else %}
        {{ log("✓ " ~ expected_obj ~ " granted to " ~ share_name, info=True) }}
      {% endif %}
    {% endfor %}
  {% endfor %}

  {{ log("All grants verified successfully!", info=True) }}
{% endmacro %}
