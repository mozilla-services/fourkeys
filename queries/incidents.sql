-- Incidents View
WITH
  github_pagerduty AS (
    SELECT
      source,
      CASE
        WHEN source LIKE "github%" THEN JSON_EXTRACT_SCALAR(metadata, '$.repository.full_name')
        WHEN source LIKE "pagerduty%" THEN JSON_EXTRACT_SCALAR(metadata, '$.event.data.service.summary')
      END
        AS metadata_service,
      CASE
        WHEN source LIKE "github%" THEN JSON_EXTRACT_SCALAR(metadata, '$.issue.number')
        WHEN source LIKE "pagerduty%" THEN JSON_EXTRACT_SCALAR(metadata, '$.event.data.id')
      END
        AS incident_id,
      CASE
        WHEN source LIKE "github%" THEN TIMESTAMP(JSON_EXTRACT_SCALAR(metadata, '$.issue.created_at'))
        WHEN source LIKE "pagerduty%" THEN TIMESTAMP(JSON_EXTRACT_SCALAR(metadata, '$.event.occurred_at'))
      END
        AS time_created,
      CASE
        WHEN source LIKE "github%" THEN TIMESTAMP(JSON_EXTRACT_SCALAR(metadata, '$.issue.closed_at'))
        WHEN source LIKE "pagerduty%" THEN TIMESTAMP(JSON_EXTRACT_SCALAR(metadata, '$.event.occurred_at'))
      END
        AS time_resolved,
      REGEXP_EXTRACT(metadata, r"root cause: ([[:alnum:]]*)") AS root_cause,
      CASE
        WHEN source LIKE "github%" THEN REGEXP_CONTAINS(JSON_EXTRACT(metadata, '$.issue.labels'), '"name":"Incident"')
        WHEN source LIKE "pagerduty%" THEN TRUE # All Pager Duty events are incident-related
      END
        AS bug,
    FROM
      four_keys.events_raw
    WHERE
      event_type LIKE "issue%"
      OR event_type LIKE "incident%"
      OR (event_type = "note" AND JSON_EXTRACT_SCALAR(metadata, '$.object_attributes.noteable_type') = 'Issue')
  ),
  issue AS (
    SELECT
      *
    FROM
      github_pagerduty
    UNION ALL
    SELECT
      source,
      github_repo AS metadata_service,
      incident_id,
      time_created,
      time_resolved,
      root_cause,
      TRUE as bug,
    FROM
      `four_keys.incidents_google_form`
  )
SELECT
  source,
  metadata_service,
  service_catalog.service,
  incident_id,
  root.environment as deployment_environment,
  MIN(IF(root.time_created < issue.time_created, root.time_created, issue.time_created)) AS time_created,
  MAX(time_resolved) AS time_resolved,
  ARRAY_AGG(root_cause IGNORE NULLS) AS changes,
FROM
  issue
LEFT JOIN
  `four_keys.services` AS service_catalog
ON
  CASE
    WHEN issue.source = "pagerduty" THEN issue.metadata_service = service_catalog.pagerduty_service
    WHEN issue.source = "github" THEN issue.metadata_service = service_catalog.github_repository
    WHEN issue.source = "google_form" THEN issue.metadata_service = service_catalog.github_repository
    ELSE FALSE
  END
LEFT JOIN (
  SELECT
    time_created,
    changes,
    service,
    environment
  FROM
    four_keys.deployments d,
    d.changes
) AS root
ON
  ( service_catalog.service = root.service AND root_cause = root.changes )
GROUP BY
  1,
  2,
  3,
  4,
  5
HAVING
  MAX(bug) IS TRUE ;
