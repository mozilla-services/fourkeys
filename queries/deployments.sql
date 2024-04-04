-- Deployments View: For GitHub `deploy_id` is the ID of the Deployment Status.
WITH
  deploys AS (  -- Cloud Build, GitHub, ArgoCD
    SELECT
      source,
      CASE
        WHEN source LIKE "github%" THEN JSON_EXTRACT_SCALAR(metadata, '$.repository.full_name')
      END
        AS metadata_service,
      CASE
        WHEN source LIKE "github%" THEN JSON_EXTRACT_SCALAR(metadata, '$.deployment_status.environment')
      END
        AS metadata_environment,
      id AS deploy_id,
      time_created,
      CASE
        WHEN source = "cloud_build" THEN JSON_EXTRACT_SCALAR(metadata, '$.substitutions.COMMIT_SHA')
        WHEN source LIKE "github%" THEN JSON_EXTRACT_SCALAR(metadata, '$.deployment.sha')
        WHEN source = "argocd" THEN JSON_EXTRACT_SCALAR(metadata, '$.commit_sha')
      END
        AS main_commit,
      CASE
        WHEN source LIKE "github%" THEN ARRAY( SELECT JSON_EXTRACT_SCALAR(string_element, '$') FROM UNNEST(JSON_EXTRACT_ARRAY(metadata, '$.deployment.additional_sha')) AS string_element)
      ELSE
        ARRAY<string>[]
      END
        AS additional_commits
    FROM
      `four_keys.events_raw`
    WHERE
      (
        -- Cloud Build Deployments
        (source = "cloud_build" AND JSON_EXTRACT_SCALAR(metadata, '$.status') = "SUCCESS")
        -- GitHub Deployments
        OR (source LIKE "github%" AND event_type = "deployment_status" AND JSON_EXTRACT_SCALAR(metadata, '$.deployment_status.state') = "success")
        -- ArgoCD Deployments
        OR (source = "argocd" AND JSON_EXTRACT_SCALAR(metadata, '$.status') = "SUCCESS")
      )
  ),
  deploys_with_service AS (
    SELECT
      deploys.*,
      service_catalog.service,
    FROM
      deploys
    LEFT JOIN
      `four_keys.services` AS service_catalog
    ON
      CASE
        WHEN deploys.source = "pagerduty" THEN deploys.metadata_service = service_catalog.pagerduty_service
        WHEN deploys.source = "github" THEN deploys.metadata_service = service_catalog.github_repository
        ELSE FALSE
      END
  ),
  changes_raw AS (
    SELECT
      source,
      id,
      metadata AS change_metadata,
      CASE
        WHEN source LIKE "github%" THEN JSON_EXTRACT_SCALAR(metadata, '$.repository.full_name')
      END
        AS metadata_service
    FROM
      `four_keys.events_raw`
  ),
  changes_raw_with_service AS (
    SELECT
      changes_raw.*,
      service_catalog.service,
    FROM
      changes_raw
    LEFT JOIN
      `four_keys.services` AS service_catalog
    ON
      CASE
        WHEN changes_raw.source = "pagerduty" THEN changes_raw.metadata_service = service_catalog.pagerduty_service
        WHEN changes_raw.source = "github" THEN changes_raw.metadata_service = service_catalog.github_repository
        ELSE FALSE
      END
  ),
  deployment_changes AS (
    SELECT
      deploys.source,
      deploys.service,
      deploys.metadata_service as deploys_service,
      changes_raw.metadata_service as changes_service,
      deploys.metadata_environment as environment,
      deploy_id,
      deploys.time_created time_created,
      change_metadata,
      four_keys.json2array(JSON_EXTRACT(change_metadata, '$.commits')) AS array_commits,
      main_commit
    FROM
      deploys_with_service as deploys
    JOIN
      changes_raw_with_service as changes_raw
    ON
      ( changes_raw.service = deploys.service ) AND ( changes_raw.id = deploys.main_commit OR changes_raw.id IN UNNEST(deploys.additional_commits) )
  )
SELECT
  source,
  service,
  deploys_service,
  changes_service,
  environment,
  deploy_id,
  time_created,
  main_commit,
  ARRAY_AGG(DISTINCT JSON_EXTRACT_SCALAR(array_commits, '$.id')) AS changes,
FROM
  deployment_changes
CROSS JOIN
  deployment_changes.array_commits
GROUP BY
  1,
  2,
  3,
  4,
  5,
  6,
  7,
  8;
