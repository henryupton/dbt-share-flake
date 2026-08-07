{#
  Retrieves the current configuration of a Snowflake share.

  Args:
    share_name (str): Name of the share to read

  Returns:
    dict: {'accounts': list, 'share_restrictions': none}

  Description:
    Reads the consumer accounts from SHOW SHARES, not DESCRIBE SHARE.

    DESCRIBE SHARE reports the objects *inside* an outbound share (the DATABASE, SCHEMA
    and TABLE rows), never the accounts it is shared with. Reading accounts from it
    therefore always returned an empty set, which made every run re-issue ADD ACCOUNTS
    for accounts that were already attached and — far worse — made it impossible to
    detect an account that should be removed. Deleting an account from configuration
    silently did nothing, so a share looked declarative while offboarding a consumer
    quietly failed.

    SHOW SHARES carries the consumer list in its `to` column, comma-separated and upper
    -cased, e.g. 'IEDKCNV.UNWRAP_US_EAST,MZ50622.SHUTTERSTOCK'. Row selection is the same
    as share_exists: narrow with LIKE, then match in Jinja via identifier_matches, because
    '_' is a single-character wildcard so the pattern over-matches siblings, and because
    Snowflake may report the name account-qualified. Inbound shares are excluded — a
    consumed share has no consumer list of ours to manage.

    share_restrictions is returned as none, meaning "not known". Snowflake exposes it
    nowhere readable — it is absent from SHOW SHARES and from DESCRIBE SHARE, and is only
    ever accepted as a modifier on ALTER SHARE ... ADD ACCOUNTS. Reporting it as false
    would be a claim rather than a reading, and would make diff_share_configuration warn
    on every run for any share configured with restrictions on.
#}
{% macro get_share_configuration(share_name) %}
  {% if not execute %}
    {{ return({}) }}
  {% endif %}

  {% set share = dbt_share_flake.validate_identifier(share_name, 'share name') %}

  {% set query %}
    SHOW SHARES LIKE '{{ share }}'
  {% endset %}

  {% set results = run_query(query) %}

  {% set config = {
    'accounts': [],
    'share_restrictions': none
  } %}

  {% for row in results %}
    {% set kind = (row.get('kind', '') | string) | upper %}
    {% if kind != 'INBOUND' and dbt_share_flake.identifier_matches(row.get('name', ''), share) %}
      {% for account in ((row.get('to', '') or '') | string).split(',') %}
        {% set trimmed = account | trim %}
        {% if trimmed %}
          {% do config['accounts'].append(trimmed) %}
        {% endif %}
      {% endfor %}
    {% endif %}
  {% endfor %}

  {{ return(config) }}
{% endmacro %}
