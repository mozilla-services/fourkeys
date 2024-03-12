-- Deployments View: For GitHub `deploy_id` is the ID of the Deployment Status.
WITH
  deploys_cloudbuild_github AS (  -- Cloud Build, GitHub, ArgoCD
    SELECT
      source,
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
      four_keys.events_raw
    WHERE
      (
        -- Cloud Build Deployments
        (source = "cloud_build" AND JSON_EXTRACT_SCALAR(metadata, '$.status') = "SUCCESS")
        -- GitHub Deployments
        OR (source LIKE "github%" AND event_type = "deployment_status" AND JSON_EXTRACT_SCALAR(metadata, '$.deployment_status.state') = "success")
        -- ArgoCD Deployments
        OR (source = "argocd" AND JSON_EXTRACT_SCALAR(metadata, '$.status') = "SUCCESS") )
  ),
  deploys_circleci AS (  -- CircleCI pipelines
    SELECT
      source,
      id AS deploy_id,
      time_created,
      JSON_EXTRACT_SCALAR(metadata, '$.pipeline.vcs.revision') AS main_commit,
      ARRAY<string>[] AS additional_commits
    FROM
      four_keys.events_raw
    WHERE
      (source = "circleci"
        AND event_type = "workflow-completed"
        AND JSON_EXTRACT_SCALAR(metadata, '$.workflow.name') LIKE "%deploy%"
        AND JSON_EXTRACT_SCALAR(metadata, '$.workflow.status') = "success")
  ),
  deploys AS (
    SELECT
      *
    FROM
      deploys_cloudbuild_github
    UNION ALL
    SELECT
      *
    FROM
      deploys_circleci
  ),
  changes_raw AS (
    SELECT
      id,
      metadata AS change_metadata
    FROM
      four_keys.events_raw
  ),
  deployment_changes AS (
    SELECT
      source,
      deploy_id,
      deploys.time_created time_created,
      change_metadata,
      four_keys.json2array(JSON_EXTRACT(change_metadata, '$.commits')) AS array_commits,
      main_commit
    FROM
      deploys
    JOIN
      changes_raw
    ON
      ( changes_raw.id = deploys.main_commit OR changes_raw.id IN UNNEST(deploys.additional_commits) )
  )
SELECT
  source,
  deploy_id,
  time_created,
  CASE
    WHEN source LIKE "github%" THEN JSON_EXTRACT_SCALAR(change_metadata, '$.repository.full_name')
  END
    AS service,
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
  5;
