#!/bin/bash
set -e

# Integration test runner for dbt-share-flake

echo "====================================="
echo "Running Integration Tests"
echo "====================================="

# Check required environment variables
required_vars=("SNOWFLAKE_ACCOUNT" "SNOWFLAKE_USER" "SNOWFLAKE_PASSWORD" "SNOWFLAKE_ROLE" "SNOWFLAKE_WAREHOUSE")
for var in "${required_vars[@]}"; do
  if [ -z "${!var}" ]; then
    echo "ERROR: Required environment variable $var is not set"
    exit 1
  fi
done

# Navigate to integration tests directory
cd "$(dirname "$0")"

echo ""
echo "Step 1: Installing dbt dependencies"
dbt deps --profiles-dir .

echo ""
echo "Step 2: Running dbt models"
dbt run --profiles-dir .

echo ""
echo "Step 3: Verifying shares were created"
dbt run-operation verify_shares --profiles-dir .

echo ""
echo "Step 4: Verifying grants were applied"
dbt run-operation verify_grants --profiles-dir .

echo ""
echo "====================================="
echo "Integration Tests Completed Successfully!"
echo "====================================="
