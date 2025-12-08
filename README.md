# dbt Snowflake Share Grants

A dbt package for automatically managing grants to Snowflake shares after dbt runs.

## Features

- Define shares at the project level with mappings to target accounts
- Specify which shares can access each model via metadata
- Automatically apply grants after `dbt run` completes
- Support for both models and snapshots

## Installation

Add this package to your `packages.yml`:

```yaml
packages:
  - git: "https://github.com/henryupton/dbt-share-flake.git"
    revision: 0.0.3
```

Then run:
```bash
dbt deps
```

## Configuration

### 1. Define Shares in dbt_project.yml

Configure your shares by adding them to your project variables. Each share includes a list of target accounts and optional share restrictions:

```yaml
vars:
  snowflake_shares:
    partner_share:
      accounts:
        - "ABC12345"
        - "XYZ67890"
      share_restrictions: false
    customer_share:
      accounts:
        - "DEF11111"
      share_restrictions: true
```

**Configuration options:**
- `accounts`: List of Snowflake account identifiers to grant the share to
- `share_restrictions`: Whether to enable share restrictions (true/false)

**Note:** Make sure the shares exist in Snowflake before running dbt. You can create them with:
```sql
CREATE SHARE partner_share;
ALTER SHARE partner_share ADD ACCOUNTS = ABC12345, XYZ67890;
```

### 3. Configure Models

Add share access to your models using the `meta` configuration:

**In a model file (e.g., `models/my_model.sql`):**

```sql
{{
  config(
    materialized='table',
    meta={
      'shares': ['partner_share', 'customer_share']
    }
  )
}}

SELECT * FROM {{ ref('raw_data') }}
```

**Or in `schema.yml`:**

```yaml
models:
  - name: my_model
    meta:
      shares:
        - partner_share
        - customer_share
```

## Usage

Once configured, the package will automatically apply grants after each `dbt run`:

```bash
dbt run
```

You'll see output like:
```
Processing Snowflake share grants...
Granting access to ANALYTICS.PUBLIC.MY_MODEL for share partner_share
Granting access to ANALYTICS.PUBLIC.MY_MODEL for share customer_share
Successfully applied 2 share grants
```

## How It Works

1. The package uses an `on-run-end` hook that executes after your dbt run completes
2. It iterates through all models and snapshots in the graph
3. For each model with `shares` metadata, it collects the required grants (databases, schemas, and objects)
4. **Revocation**: For each share, it queries existing grants and revokes any that are no longer in your configuration
5. **Grant application**: It applies grants in the correct order:
   - `USAGE` on databases
   - `USAGE` on schemas
   - `SELECT` on tables/views

This ensures your shares stay in sync with your dbt configuration - grants are added when models are added to shares, and automatically removed when models are removed from shares.

## Example Project Structure

```
my_dbt_project/
├── dbt_project.yml          # Define shares here
├── models/
│   ├── schema.yml           # Or define shares here
│   └── shared_model.sql     # Models to share
└── packages.yml             # Install this package
```

## Permissions

The Snowflake user running dbt must have the `OWNERSHIP` privilege on the shares to apply grants:

```sql
GRANT OWNERSHIP ON SHARE partner_share TO ROLE dbt_role;
```

## Troubleshooting

**Warning: Share 'X' referenced but not defined**
- Ensure the share name in your model's `meta.shares` matches exactly with the key in `snowflake_shares` variable

**Permission denied when applying grants**
- Verify your Snowflake user has ownership or appropriate privileges on the share
- Check that the share exists in Snowflake

**Grants not being applied**
- Confirm the `on-run-end` hook is configured in your `dbt_project.yml`
- Make sure models have the `shares` array in their metadata

## Advanced Usage

### Conditional Shares by Environment

You can use dbt's variable system to configure different shares per environment:

```yaml
# dbt_project.yml
vars:
  snowflake_shares: "{{ var('shares_' ~ target.name, {}) }}"

  shares_prod:
    partner_share:
      accounts:
        - "ABC12345"
      share_restrictions: false

  shares_dev:
    dev_share:
      accounts:
        - "TEST12345"
      share_restrictions: false
```

### Adding Shares to Existing Databases

To share entire databases or schemas (not just individual tables), you can manually add them to the share:

```sql
ALTER SHARE partner_share ADD DATABASE analytics;
```

Then use this package to selectively grant access to specific tables within that database.

## License

MIT
