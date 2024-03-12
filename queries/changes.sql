-- Changes View: The `change_id` field is a Git commit's ID
SELECT
  source,
  event_type,
  JSON_EXTRACT_SCALAR(commit, '$.id') AS change_id,
  TIMESTAMP_TRUNC(TIMESTAMP(JSON_EXTRACT_SCALAR(commit, '$.timestamp')),second) AS time_created,
FROM
  four_keys.events_raw e,
  UNNEST(JSON_EXTRACT_ARRAY(e.metadata, '$.commits')) AS commit
WHERE
  event_type = "push"
GROUP BY
  1,
  2,
  3,
  4
