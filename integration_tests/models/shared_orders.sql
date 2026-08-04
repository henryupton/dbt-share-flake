{{
  config(
    materialized='view',
    meta={
      'shares': ['test_share_1']
    }
  )
}}

SELECT
  1 as order_id,
  1 as customer_id,
  100.00 as amount,
  current_timestamp() as order_date
UNION ALL
SELECT
  2 as order_id,
  2 as customer_id,
  200.00 as amount,
  current_timestamp() as order_date
