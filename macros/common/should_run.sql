{#
  Decides whether share and listing management should run at all.

  Args:
    None - reads snowflake_sharing_enabled and snowflake_sharing_targets

  Returns:
    bool: True if the current invocation should manage shares and listings

  Description:
    Single gate for every entrypoint into the package. Returns false, logging the
    reason, when any of the following hold:
      - we are in dbt's parse phase rather than execution
      - snowflake_sharing_enabled is false
      - the current command is not one that materialises relations
      - snowflake_sharing_targets is set and the active target is not in it

    The target allowlist is the safety rail that stops a developer's `dbt run`
    against a personal target from creating or mutating real shares.
#}
{% macro should_run() %}
  {% if not execute %}
    {{ return(false) }}
  {% endif %}

  {% if not var('snowflake_sharing_enabled', true) %}
    {{ log("dbt-share-flake: skipping, disabled via snowflake_sharing_enabled", info=True) }}
    {{ return(false) }}
  {% endif %}

  {% set allowed_commands = ['run', 'build', 'run-operation', 'snapshot'] %}
  {% if flags.WHICH not in allowed_commands %}
    {{ log("dbt-share-flake: skipping, only runs during: " ~ allowed_commands | join(', '), info=True) }}
    {{ return(false) }}
  {% endif %}

  {% set allowed_targets = var('snowflake_sharing_targets', none) %}
  {% if allowed_targets is not none %}
    {% if allowed_targets is string %}
      {% set allowed_targets = [allowed_targets] %}
    {% endif %}
    {% if target.name not in allowed_targets %}
      {{ log(
        "dbt-share-flake: skipping, target '" ~ target.name ~ "' is not in "
        ~ "snowflake_sharing_targets (" ~ allowed_targets | join(', ') ~ ")", info=True
      ) }}
      {{ return(false) }}
    {% endif %}
  {% endif %}

  {{ return(true) }}
{% endmacro %}
