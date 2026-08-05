{{
  config(
    materialized='table'
  )
}}

-- This model has no shares configured and should not be granted to any share

SELECT
  1 as id,
  'internal_data' as data
