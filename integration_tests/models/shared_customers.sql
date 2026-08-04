{{
  config(
    materialized='incremental',
    meta={
      'shares': ['test_share_1']
    }
  )
}}

SELECT
  1 as customer_id,
  'Alice' as customer_name,
  'alice@example.com' as email
UNION ALL
SELECT
  2 as customer_id,
  'Bob' as customer_name,
  'bob@example.com' as email
