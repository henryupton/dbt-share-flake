# dbt Snowflake Share & Listing Manager

[![Tests](https://github.com/henryupton/dbt-share-flake/actions/workflows/test.yml/badge.svg)](https://github.com/henryupton/dbt-share-flake/actions/workflows/test.yml)

A dbt package for automatically managing grants to Snowflake shares and listings after dbt runs.

## Features

**Shares (Direct Sharing)**
- Define shares at the project level with mappings to target accounts
- Specify which shares can access each model via metadata
- Automatically apply grants after `dbt run` completes
- Support for both models and snapshots

**Listings (Marketplace)**
- Define Snowflake Data Marketplace listings with title and description
- Automatically create underlying shares for listings
- Specify which models to include in listings via metadata
- Independent from shares - use one or both as needed

## Installation

Add this package to your `packages.yml`:

```yaml
packages:
  - git: "https://github.com/henryupton/dbt-share-flake.git"
    revision: 0.0.9
```

Then run:
```bash
dbt deps
```

## Configuration

### 1. Define Shares (Direct Sharing)

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

### 2. Define Listings (Organization/Internal)

Configure Snowflake organization listings for internal or partner data sharing. Each listing automatically creates an underlying share:

```yaml
vars:
  snowflake_listings:
    internal_analytics:
      title: "Internal Analytics Data"
      description: "For internal BI and reporting"
      organization_profile: "INTERNAL"              # INTERNAL (default) or EXTERNAL
      organization_targets:
        discovery:                                   # Who can see the listing exists
          - account: "ABC123"
            roles: ["ANALYST_ROLE", "DATA_SCIENTIST"]
        access:                                      # Who can actually consume the data
          - account: "ABC123"
            roles: ["ANALYST_ROLE"]
      support_contact: "data-team@company.com"      # Optional
      approver_contact: "data-governance@company.com" # Optional
      locations:                                     # Optional
        access_regions:
          - name: "PUBLIC.AWS_US_WEST_2"
```

**Configuration options:**
- `title`: Display title for the listing *(required)*
- `description`: Description shown to consumers *(required)*
- `organization_profile`: "INTERNAL" for within organization, "EXTERNAL" for partners *(defaults to INTERNAL)*
- `organization_targets`: Controls who can discover and access the listing
  - `discovery`: Accounts/roles that can see the listing exists
  - `access`: Accounts/roles that can consume the data
- `support_contact`: Email for data support inquiries *(optional)*
- `approver_contact`: Email for approval requests *(optional)*
- `locations`: Snowflake regions where data is accessible *(optional)*

**Auto-created shares:** Each listing automatically creates a share named `{listing_name}_share`. For example, `internal_analytics` creates `internal_analytics_share`. You don't need to configure these shares separately.

### 3. Configure Models

Add share and/or listing access to your models using the `meta` configuration:

**Direct share access only:**
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

**Marketplace listing only:**
```sql
{{
  config(
    materialized='view',
    meta={
      'listings': ['marketplace_listing']
    }
  )
}}

SELECT * FROM {{ ref('analytics_data') }}
```

**Both share and listing (model available via both mechanisms):**
```sql
{{
  config(
    materialized='table',
    meta={
      'shares': ['partner_share'],
      'listings': ['marketplace_listing']
    }
  )
}}

SELECT * FROM {{ ref('shared_data') }}
```

**Or in `schema.yml`:**
```yaml
models:
  - name: my_model
    meta:
      shares:
        - partner_share
      listings:
        - marketplace_listing
```

## Usage

Once configured, the package will automatically apply grants after each `dbt run`:

```bash
dbt run
```

The full plan is logged before anything is executed:
```
dbt-share-flake: 4 to grant, 1 to revoke
dbt-share-flake:   share partner_share
dbt-share-flake:     + grant  usage  on database analytics
dbt-share-flake:     + grant  usage  on schema   analytics.public
dbt-share-flake:     + grant  select on table    analytics.public.orders
dbt-share-flake:     - revoke select on table    analytics.public.legacy
dbt-share-flake:     ~ add accounts ABC12345 (share_restrictions = FALSE)
```

To see that plan without touching anything, set `snowflake_sharing_dry_run: true`.

## How It Works

### Execution Flow

1. The package uses an `on-run-end` hook that executes after your dbt run completes
2. **Listings are processed first** (if configured):
   - Creates underlying shares (e.g., `marketplace_listing_share`)
   - Creates listings that reference those shares
   - Optionally updates listing metadata (title, description)
3. **Shares are processed second**, as plan then apply:
   - Walks the dbt graph once, building the desired grants for every share
   - Reads the existing grants on each share and diffs them
   - Applies the safety guards below, and aborts before changing anything if a guard trips
   - Logs the plan
   - Executes it: create share, revoke, grant, then reconcile accounts
   - Grants are applied containers-first (`USAGE` on database, `USAGE` on schema,
     `SELECT` on the relation) and revoked in the reverse order

This ensures your shares and listings stay in sync with your dbt configuration - grants are added when models are added, and automatically removed when models are removed.

### Safety Rails

Revocation is the one operation here that can break a live consumer, and the desired
state is derived from the dbt graph. So anything that narrows the graph without
narrowing your intent makes still-wanted grants look like deletions. The package
therefore **skips revocation by default** when:

- the run used `--select`, `--exclude` or `--selector`
- any node in the run errored, failed or was skipped (including failing tests)
- the plan would revoke more than `snowflake_sharing_max_revokes` grants, in which case
  the run aborts before executing anything

Grants are always still applied in those cases; only the revocations wait for a clean
full run. Each skip is logged with the variable that overrides it.

Grants belonging to a model that did not succeed this run are held back, since the
relation may not exist. Database and schema grants are only held back if *every* model
that needs them failed, so one broken model does not strip its neighbours' access.

Set `snowflake_sharing_targets` to restrict the whole package to named targets. Without
it, a developer's `dbt run` against a personal target will create and mutate real shares.

### Shares vs Listings

**Shares (Direct Sharing):**
- Explicitly shared with specific Snowflake accounts
- Configure target accounts in `snowflake_shares`
- Models use `meta.shares` to opt-in

**Listings (Marketplace):**
- Published to Snowflake Data Marketplace
- Each listing creates an underlying share automatically
- Models use `meta.listings` to opt-in
- Listing metadata (title, description) managed by package

**Independence:** These are separate mechanisms. You can:
- Use shares without listings (direct sharing only)
- Use listings without shares (marketplace only)
- Use both for different models
- Use both for the same model (available via direct share AND marketplace)

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

### For Shares
The Snowflake user running dbt must have:
```sql
GRANT CREATE SHARE ON ACCOUNT TO ROLE dbt_role;
GRANT IMPORT SHARE ON ACCOUNT TO ROLE dbt_role;
GRANT MANAGE GRANTS ON ACCOUNT TO ROLE dbt_role;
GRANT MANAGE SHARE TARGET ON ACCOUNT TO ROLE dbt_role;
```

### For Listings
The Snowflake user running dbt must additionally have:
```sql
GRANT CREATE LISTING ON ACCOUNT TO ROLE dbt_role;
-- MODIFY privilege will be needed on each listing
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

## Control Variables

### Safety

```yaml
vars:
  snowflake_sharing_enabled: true    # Master switch (default: true)
  snowflake_sharing_dry_run: false   # Log the plan, execute nothing (default: false)
  snowflake_sharing_targets: ["prod"] # Only run against these targets (default: all targets)

  snowflake_sharing_allow_revoke: true              # Allow revocation at all (default: true)
  snowflake_sharing_max_revokes: 20                 # Abort above this many revokes (default: 20)
  snowflake_sharing_revoke_on_partial_selection: false  # Revoke during --select runs (default: false)
  snowflake_sharing_revoke_after_failure: false     # Revoke when nodes failed (default: false)
```

- `snowflake_sharing_targets` accepts a list or a single string. Strongly recommended:
  without it, any target can create and mutate real shares.
- `snowflake_sharing_max_revokes` aborts the run with an error listing what it would
  have revoked, before executing anything. Set it to `none` to disable the ceiling.
- Setting `snowflake_sharing_allow_revoke: false` applies grants but never removes any,
  which is the right setting if more than one project grants to the same share.

### Privilege Checks
```yaml
vars:
  snowflake_shares_check_privileges: true   # Check share privileges (default: true)
  snowflake_listings_check_privileges: true # Check listing privileges (default: true)
```

Note that this only inspects privileges granted *directly* to the current role, so a
role that inherits them through a role hierarchy will warn spuriously. The check is
advisory: it warns and continues.

### Alter Operations
```yaml
vars:
  snowflake_shares_alter_share: false      # Update share accounts/restrictions (default: false)
  snowflake_listings_alter_listing: false  # Update listing metadata (default: false)
```

Set `alter_share` / `alter_listing` to `true` to enable automatic updates when
configuration changes. By default, shares and listings are created but not modified
after creation.

These gate *subsequent* changes only. A share the package creates always receives its
configured `accounts` and `share_restrictions`, because a share with no accounts is
unusable.

With `alter_share: true`, the consumer list is genuinely declarative in both directions:
removing an account from `accounts` revokes that consumer's access on the next run. The
existing list is read from the `to` column of `SHOW SHARES`.

### A note on `share_restrictions`

Snowflake only accepts `SHARE_RESTRICTIONS` as a modifier on `ALTER SHARE ... ADD
ACCOUNTS`, not as a settable property of an existing share. The package emits it
alongside every account addition. Changing it on a share whose account list is not
changing warns instead, since there is no DDL that would do it.

It is also not readable back: Snowflake reports it in neither `SHOW SHARES` nor
`DESCRIBE SHARE`. The package therefore treats the current value of an existing share as
unknown rather than assuming `false`, so it never reports a change it could not apply.

## Naming Rules

Share, listing and role names must be plain unquoted Snowflake identifiers: a letter or
underscore followed by letters, digits, underscores or dollar signs. Account identifiers
may also contain dots and hyphens, for the `MYORG.MY_ACCOUNT` form. Anything else is
rejected with a compiler error rather than being quoted or escaped, because these values
are interpolated into DDL and quoting them would silently change their case semantics.

Listing titles and descriptions are free text and are escaped for the YAML manifest,
except that they may not contain `$$`, which would terminate the SQL block early.

## License

MIT
