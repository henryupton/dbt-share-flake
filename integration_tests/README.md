# Integration Tests

This directory contains integration tests for the dbt-share-flake package.

## Prerequisites

1. **Snowflake Account**: You need access to a Snowflake account with permissions to:
   - Create shares
   - Grant privileges on databases, schemas, and tables
   - Manage share configurations

2. **dbt Installed**: Ensure you have dbt-snowflake installed:
   ```bash
   pip install dbt-snowflake
   ```

## Setup

### 1. Set Environment Variables

Create a `.env` file or export these variables:

```bash
# Required
export SNOWFLAKE_ACCOUNT="your_account"
export SNOWFLAKE_USER="your_username"
export SNOWFLAKE_PASSWORD="your_password"
export SNOWFLAKE_ROLE="your_role"
export SNOWFLAKE_WAREHOUSE="your_warehouse"

# Optional (will use defaults if not set)
export SNOWFLAKE_DATABASE="DBT_SHARE_TEST"
export SNOWFLAKE_SCHEMA="PUBLIC"

# Test account identifiers for shares
export TEST_ACCOUNT_1="TEST_ACCOUNT_1"
export TEST_ACCOUNT_2="TEST_ACCOUNT_2"
```

### 2. Verify Permissions

Ensure your Snowflake role has the following privileges:

```sql
-- Check your current privileges
SHOW GRANTS TO ROLE YOUR_ROLE;

-- Required privileges
-- CREATE SHARE
-- CREATE DATABASE (or use existing database)
-- CREATE SCHEMA (or use existing schema)
-- CREATE TABLE
-- CREATE VIEW
```

## Running Tests

### Automated Test Run

Execute all tests with the provided script:

```bash
cd integration_tests
./run_tests.sh
```

### Manual Test Run

Or run tests step-by-step:

```bash
cd integration_tests

# Install dependencies
dbt deps --profiles-dir .

# Run models (this will trigger share management via on-run-end hook)
dbt run --profiles-dir .

# Verify shares were created
dbt run-operation verify_shares --profiles-dir .

# Verify grants were applied correctly
dbt run-operation verify_grants --profiles-dir .
```

## Test Coverage

The integration tests verify:

1. **Share Creation**: Shares are created if they don't exist
2. **Share Configuration**: Account lists and share_restrictions are properly set
3. **Grant Application**: Models with `shares` metadata receive proper grants
4. **Database/Schema Grants**: USAGE grants are applied to databases and schemas
5. **Selective Grants**: Only models with share metadata are granted
6. **Multi-Share Support**: Models can be granted to multiple shares

## Test Models

- **shared_customers**: Table granted to `test_share_1`
- **shared_orders**: View granted to both `test_share_1` and `test_share_2`
- **unshared_internal**: Table with no share grants (should not be shared)

## Cleanup

To clean up test resources:

```bash
cd integration_tests

# Drop the models
dbt run-operation drop_all_relations --profiles-dir .

# Manually drop shares in Snowflake
# DROP SHARE test_share_1;
# DROP SHARE test_share_2;
```

## Troubleshooting

### "Share does not exist" errors

Ensure your role has the `CREATE SHARE` privilege:
```sql
GRANT CREATE SHARE ON ACCOUNT TO ROLE your_role;
```

### "Insufficient privileges" errors

Check that your role has ownership or appropriate privileges on:
- The target database
- The target schema
- The shares being managed

### Test failures

Check the dbt logs for detailed error messages:
```bash
cat logs/dbt.log
```

## CI/CD Integration

To run these tests in CI/CD:

```yaml
# Example GitHub Actions
- name: Run Integration Tests
  env:
    SNOWFLAKE_ACCOUNT: ${{ secrets.SNOWFLAKE_ACCOUNT }}
    SNOWFLAKE_USER: ${{ secrets.SNOWFLAKE_USER }}
    SNOWFLAKE_PASSWORD: ${{ secrets.SNOWFLAKE_PASSWORD }}
    SNOWFLAKE_ROLE: ${{ secrets.SNOWFLAKE_ROLE }}
    SNOWFLAKE_WAREHOUSE: ${{ secrets.SNOWFLAKE_WAREHOUSE }}
  run: |
    cd integration_tests
    ./run_tests.sh
```
