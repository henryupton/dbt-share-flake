{{
  config(
    materialized='table',
    meta={
      'listings': ['test_listing_1']
    }
  )
}}

SELECT
  1 as product_id,
  'Widget' as product_name,
  29.99 as price
UNION ALL
SELECT
  2 as product_id,
  'Gadget' as product_name,
  49.99 as price
