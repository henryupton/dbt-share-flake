{#
  Builds YAML manifest for organization listing creation/update.

  Args:
    listing_config (dict): Listing configuration with all organization listing fields

  Returns:
    str: YAML-formatted manifest string

  Description:
    Constructs a YAML manifest for CREATE ORGANIZATION LISTING.
    Includes title, description, organization_profile, organization_targets,
    support_contact, approver_contact, and locations.

    Every free-text value is escaped for YAML, and every account or role name is
    validated as an identifier. The manifest is sent inside a dollar-quoted SQL block,
    so an unescaped quote breaks the YAML and a literal '$$' would end the block early
    and let configuration text run as SQL.
#}
{% macro build_listing_manifest(listing_config) %}
  {% set manifest_lines = [] %}

  {# Required fields #}
  {% set title = listing_config.get('title', '') %}
  {% set description = listing_config.get('description', '') %}

  {% if title %}
    {% do manifest_lines.append('title: "' ~ dbt_share_flake.escape_yaml_value(title, 'title') ~ '"') %}
  {% endif %}

  {% if description %}
    {% do manifest_lines.append('description: "' ~ dbt_share_flake.escape_yaml_value(description, 'description') ~ '"') %}
  {% endif %}

  {# Organization profile (INTERNAL or EXTERNAL) - defaults to INTERNAL #}
  {% set org_profile = listing_config.get('organization_profile', 'INTERNAL') | upper %}
  {% if org_profile not in ['INTERNAL', 'EXTERNAL'] %}
    {{ exceptions.raise_compiler_error(
      "dbt-share-flake: organization_profile must be 'INTERNAL' or 'EXTERNAL', got '" ~ org_profile ~ "'"
    ) }}
  {% endif %}
  {% do manifest_lines.append('organization_profile: "' ~ org_profile ~ '"') %}

  {# Organization targets (discovery and access) #}
  {% set org_targets = listing_config.get('organization_targets', none) %}
  {% if org_targets %}
    {% do manifest_lines.append('organization_targets:') %}

    {% for target_kind in ['discovery', 'access'] %}
      {% if org_targets.get(target_kind) %}
        {% do manifest_lines.append('  ' ~ target_kind ~ ':') %}
        {% for target in org_targets.get(target_kind, []) %}
          {% set account = dbt_share_flake.validate_account(target.get('account', '')) %}
          {% do manifest_lines.append('    - account: "' ~ account ~ '"') %}
          {% if target.get('roles') %}
            {% do manifest_lines.append('      roles:') %}
            {% for role in target.get('roles', []) %}
              {% do manifest_lines.append('        - "' ~ dbt_share_flake.validate_identifier(role, 'role name') ~ '"') %}
            {% endfor %}
          {% endif %}
        {% endfor %}
      {% endif %}
    {% endfor %}
  {% endif %}

  {# Contact information #}
  {% set support_contact = listing_config.get('support_contact', none) %}
  {% if support_contact %}
    {% do manifest_lines.append('support_contact: "' ~ dbt_share_flake.escape_yaml_value(support_contact, 'support_contact') ~ '"') %}
  {% endif %}

  {% set approver_contact = listing_config.get('approver_contact', none) %}
  {% if approver_contact %}
    {% do manifest_lines.append('approver_contact: "' ~ dbt_share_flake.escape_yaml_value(approver_contact, 'approver_contact') ~ '"') %}
  {% endif %}

  {# Locations (access regions) #}
  {% set locations = listing_config.get('locations', none) %}
  {% if locations and locations.get('access_regions') %}
    {% do manifest_lines.append('locations:') %}
    {% do manifest_lines.append('  access_regions:') %}
    {% for region in locations.get('access_regions', []) %}
      {% do manifest_lines.append('    - name: "' ~ dbt_share_flake.escape_yaml_value(region.get('name', ''), 'access region name') ~ '"') %}
    {% endfor %}
  {% endif %}

  {{ return(manifest_lines | join('\n')) }}
{% endmacro %}
