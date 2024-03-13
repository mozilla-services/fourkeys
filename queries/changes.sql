-- Changes View: The `change_id` field is a Git commit's ID
SELECT
  source,
  event_type,
  CASE
    WHEN source LIKE "github%" THEN JSON_EXTRACT_SCALAR(metadata, '$.repository.full_name')
  END
    AS service,
  JSON_EXTRACT_SCALAR(commit, '$.id') AS change_id,
  TIMESTAMP_TRUNC(TIMESTAMP(JSON_EXTRACT_SCALAR(commit, '$.timestamp')),second) AS time_created
FROM
  four_keys.events_raw e,
  -- Create a row for each element in the array of `commits` from the `metadata` field.
  -- The other fields in the row are repeated for each `commit`.
  UNNEST(JSON_EXTRACT_ARRAY(e.metadata, '$.commits')) AS commit
WHERE
  event_type = "push"
GROUP BY
  1,
  2,
  3,
  4,
  5
