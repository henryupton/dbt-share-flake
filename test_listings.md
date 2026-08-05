# Testing Listings Functionality

## Prerequisites

1. **Snowflake Account** with appropriate permissions
2. **Role** with required privileges:
   ```sql
   GRANT CREATE LISTING ON ACCOUNT TO ROLE <your_role>;
   GRANT CREATE SHARE ON ACCOUNT TO ROLE <your_role>;
   GRANT USAGE ON DATABASE <test_db> TO ROLE <your_role>;
   ```

## Test Scenario 1: Basic Organization Listing

### Configuration
Add to `integration_tests/dbt_project.yml`:
```yaml
vars:
  snowflake_listings:
    test_org_listing:
      title: "Test Organization Listing"
      description: "Testing internal listing creation"
      organization_profile: "INTERNAL"
      organization_targets:
        discovery:
          - account: "<your_test_account>"
            roles: ["PUBLIC"]
        access:
          - account: "<your_test_account>"
            roles: ["PUBLIC"]
```

### Model
Create `integration_tests/models/test_listing_data.sql`:
```sql
{{
  config(
    materialized='view',
    meta={
      'listings': ['test_org_listing']
    }
  )
}}

SELECT 1 as id, 'test' as name
```

### Execute
```bash
cd integration_tests
dbt run
```

### Verify
```sql
-- Check share was created
SHOW SHARES LIKE 'test_org_listing_share';

-- Check listing was created
SHOW ORGANIZATION LISTINGS LIKE 'test_org_listing';

-- Check grants on share
SHOW GRANTS TO SHARE test_org_listing_share;

-- Describe listing
DESCRIBE ORGANIZATION LISTING test_org_listing;
```

## Test Scenario 2: Multiple Listings

```yaml
vars:
  snowflake_listings:
    analytics_listing:
      title: "Analytics Data"
      description: "Internal analytics"
      organization_profile: "INTERNAL"
      organization_targets:
        discovery:
          - account: "ACCOUNT1"
            roles: ["ANALYST"]
        access:
          - account: "ACCOUNT1"
            roles: ["ANALYST"]

    partner_listing:
      title: "Partner Data Feed"
      description: "External partner data"
      organization_profile: "EXTERNAL"
      organization_targets:
        discovery:
          - account: "PARTNER_ACCOUNT"
            roles: ["DATA_CONSUMER"]
        access:
          - account: "PARTNER_ACCOUNT"
            roles: ["DATA_CONSUMER"]
```

### Model with multiple listings
```sql
{{
  config(
    materialized='table',
    meta={
      'listings': ['analytics_listing', 'partner_listing']
    }
  )
}}

SELECT * FROM source_table
```

## Test Scenario 3: Shares AND Listings

```sql
{{
  config(
    materialized='view',
    meta={
      'shares': ['direct_share'],
      'listings': ['org_listing']
    }
  )
}}

SELECT * FROM data
```

Model should be granted to:
- Share: `direct_share`
- Share: `org_listing_share` (auto-created for listing)

## Test Scenario 4: Listing Updates

1. Create listing with initial config
2. Change `title` or `description` in `dbt_project.yml`
3. Set `snowflake_listings_alter_listing: true`
4. Run `dbt run`
5. Verify listing was updated:
   ```sql
   DESCRIBE ORGANIZATION LISTING <listing_name>;
   ```

## Expected Results

### After `dbt run`:
✓ Share created: `<listing_name>_share`
✓ Organization listing created: `<listing_name>`
✓ Database USAGE granted to share
✓ Schema USAGE granted to share
✓ Model SELECT granted to share

### Verify with SQL:
```sql
-- List all organization listings
SHOW ORGANIZATION LISTINGS;

-- Check specific listing details
DESCRIBE ORGANIZATION LISTING test_org_listing;

-- Verify grants
SHOW GRANTS TO SHARE test_org_listing_share;
```

## Cleanup

```sql
-- Drop listing first (depends on share)
DROP ORGANIZATION LISTING IF EXISTS test_org_listing;

-- Then drop share
DROP SHARE IF EXISTS test_org_listing_share;
```

## Common Issues

### Permission Errors
```
SQL compilation error: Insufficient privileges to operate on account
```
**Solution**: Ensure role has `CREATE LISTING` and `CREATE SHARE` privileges

### Listing Already Exists
```
Organization listing 'TEST_ORG_LISTING' already exists
```
**Solution**: Drop existing listing or use `OR REPLACE` (not currently supported)

### Invalid Account
```
Invalid account identifier in organization_targets
```
**Solution**: Use correct Snowflake account identifier format (e.g., "ABC12345")

## Automated Testing (Future)

Consider adding:
- dbt macro tests for SQL generation
- Python tests for YAML manifest building
- CI/CD integration with ephemeral Snowflake accounts
