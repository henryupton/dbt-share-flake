{{
  config(
    materialized='view',
    meta={
      'shares': ['test_share_1'],
      'listings': ['test_listing_1']
    }
  )
}}

SELECT
  1 as item_id,
  'Item A' as item_name,
  100 as quantity
UNION ALL
SELECT
  2 as item_id,
  'Item B' as item_name,
  200 as quantity
