# Changelog

All notable changes to the LaunchDarkly REST API clients.

## [26.2.0] - 2026-11-21

### Added

- Added `createdAt` and `updatedAt` to flag release plan responses, as Unix milliseconds. Affected endpoints:
  - `GET /api/v2/projects/{projectKey}/flag-release-plans`
  - `POST /api/v2/projects/{projectKey}/flag-release-plans`
  - `GET /api/v2/projects/{projectKey}/flag-release-plans/{planKey}`
  - `PUT /api/v2/projects/{projectKey}/flag-release-plans/{planKey}`

## [26.1.0] - 2026-11-18

### Added

- Added optional `disabled` and `description` to each rule in `GET /api/v2/projects/{projectKey}/ai-configs/{configKey}/targeting` and the `PATCH` response for the same path. A disabled rule doesn't match any contexts, so it doesn't serve its variation or rollout. As in the flags API, each field is left out when the rule doesn't set it.
- Added a `creationDate` filter to `GET /api/v2/approval-requests`, for listing approval requests created before or after a time. It takes the `before` and `after` operators with Unix milliseconds or an RFC 3339 timestamp, and both are exclusive. For example, `filter=creationDate after 1794000000000` lists the approval requests created after that time.
- Added optional `tools` to agent skills, for pinning AI tools to an agent skill. On create and update, each entry is a `SkillToolRef` with the tool's `key` and an optional `version`, and leaving `version` out pins the tool's latest version at the time of the request. In responses, each entry is a `PinnedSkillToolRef`, which always includes the pinned `version`. Tools are listed in the order they reach the agent, each tool key can appear once, a skill can pin tools only from its own project, up to 20 by default, and you need read access to each tool. On `PATCH`, leaving `tools` out keeps the current tools, and sending it replaces them all; a change to the tools or their order creates a new skill version. This field is being released gradually: until it is enabled for your account, requests that send `tools` return a `400`, and responses leave it out. Affected endpoints:
  - `POST /api/v2/projects/{projectKey}/ai-configs/skills`
  - `PATCH /api/v2/projects/{projectKey}/ai-configs/skills/{skillKey}`
  - `GET /api/v2/projects/{projectKey}/ai-configs/skills`
  - `GET /api/v2/projects/{projectKey}/ai-configs/skills/{skillKey}`
  - `GET /api/v2/projects/{projectKey}/ai-configs/skills/{skillKey}/versions`
- Added optional `skills` and `skillsTotalCount` to `GET /api/v2/projects/{projectKey}/ai-tools/{toolKey}/references`. `skills` lists every agent skill version that pins a version of the tool, old versions included, as `ToolSkillReference` entries with `skillKey`, `skillVersion`, and `toolVersion`, ordered by skill key, then newest skill version first. `limit` and `offset` page `items` and `skills` separately. This field is being released gradually alongside agent skill `tools`, and responses leave it out until it is enabled for your account.
- Added a `409` response to `DELETE /api/v2/projects/{projectKey}/ai-tools/{toolKey}`. A tool can't be deleted while any version of an agent skill pins it, and the error message names those skills. Removing the tool from a skill creates a new skill version, and older versions keep their pins, so delete the skill to free the tool.

## [26.0.0] - 2026-11-14

### Added

- Added Flag release plans (beta) endpoints for creating, listing, viewing, updating, and deleting flag release plans. A flag release plan is a reusable release configuration for a flag across the environments in a project. For each environment, it sets the release order, the trigger that starts the release, and whether the release is immediate or runs an environment release plan. These are beta endpoints and require the `LD-API-Version: beta` header:
  - `GET /api/v2/projects/{projectKey}/flag-release-plans`
  - `POST /api/v2/projects/{projectKey}/flag-release-plans`
  - `GET /api/v2/projects/{projectKey}/flag-release-plans/{planKey}`
  - `PUT /api/v2/projects/{projectKey}/flag-release-plans/{planKey}`
  - `DELETE /api/v2/projects/{projectKey}/flag-release-plans/{planKey}`

### Fixed

- Fixed `GET /api/v2/projects/{projectKey}/views` ignoring `expand=aiConfigsSummary`. Each view in the list now includes `aiConfigsSummary` with the `count` of AI Configs linked to it, as documented. Previously the field was only returned by `GET /api/v2/projects/{projectKey}/views/{viewKey}`.

### Removed

- Removed the Release policies (beta) endpoints from the public API documentation. The release policies API is being shut off in favor of environment release plans, and requests return `403` after shut-off. Use the Environment release plans (beta) endpoints instead. Affected endpoints:
  - `GET /api/v2/projects/{projectKey}/release-policies`
  - `POST /api/v2/projects/{projectKey}/release-policies`
  - `POST /api/v2/projects/{projectKey}/release-policies/order`
  - `GET /api/v2/projects/{projectKey}/release-policies/{policyKey}`
  - `PUT /api/v2/projects/{projectKey}/release-policies/{policyKey}`
  - `DELETE /api/v2/projects/{projectKey}/release-policies/{policyKey}`
- Removed the unused `ReleasePoliciesAccessRep`, `ReleasePoliciesAccess`, `ReleasePoliciesAccessDenied`, `ReleasePoliciesAccessDeniedReason`, `ReleasePoliciesAccessAllowedRep`, and `ReleasePoliciesAccessAllowedReason` schemas, which were left in the public specification after the Release policies (beta) endpoints were removed. No endpoint referenced them.

## [25.2.0] - 2026-11-12

### Added

- Added optional `bearerToken` to the `POST /api/v2/webhooks` request body and to `PATCH /api/v2/webhooks/{id}`. If set, LaunchDarkly sends it in an `Authorization: Bearer` header with each webhook request. The token is write-only and is never returned. To remove it, patch `/bearerToken` with an empty string.
- Added `hasBearerToken` to the webhook object. It is `true` when the webhook sends a bearer token, and omitted otherwise. Affected endpoints:
  - `GET /api/v2/webhooks`
  - `POST /api/v2/webhooks`
  - `GET /api/v2/webhooks/{id}`
  - `PATCH /api/v2/webhooks/{id}`
- Added `_id` to each rule in `GET /api/v2/projects/{projectKey}/ai-configs/{configKey}/targeting`. It is the rule ID to pass as `ruleId` in targeting instructions that change a rule, such as `addShadowRequest`. Previously the ID was only available from the flags API.
- Documented warehouse-native assignment on experiments. These fields already existed on the API and their behavior is unchanged; they were previously left out of the spec.
  - Added optional `assignmentSourceType` to the experiment object. It is the source of assignment data for the experiment, one of `launchdarkly`, `snowflake`, `databricks`, `redshift`, `bigquery`, or `clickhouse`. It defaults to `launchdarkly`, and experiments created before warehouse-native assignment existed omit it. Affected endpoints:
    - `GET /api/v2/projects/{projectKey}/experiments`
    - `GET /api/v2/projects/{projectKey}/environments/{environmentKey}/experiments`
    - `POST /api/v2/projects/{projectKey}/environments/{environmentKey}/experiments`
    - `GET /api/v2/projects/{projectKey}/environments/{environmentKey}/experiments/{experimentKey}`
    - `PATCH /api/v2/projects/{projectKey}/environments/{environmentKey}/experiments/{experimentKey}`
    - Holdout responses that return experiment objects
  - Added optional `assignmentDataSource` to the iteration object and to iteration request bodies. It holds the assignment data source `key`, the `experimentId` to match in that source, and the optional `startTime` and `endTime` of the assignment data window. Responses also include the source's display `name`. It is omitted for experiments that assign through flags. You can also set it through the `assignmentDataSource` field on the `updateExperimentFields` instruction.
  - Added optional `assignmentVariantId` to each treatment, in both iteration request bodies and responses. It is the variant identifier in the warehouse-native assignment source that maps to that treatment.
  - Request bodies affected by `assignmentDataSource` and `assignmentVariantId`:
    - `POST /api/v2/projects/{projectKey}/environments/{environmentKey}/experiments`
    - `POST /api/v2/projects/{projectKey}/environments/{environmentKey}/experiments/{experimentKey}/iterations`
    - `PATCH /api/v2/projects/{projectKey}/environments/{environmentKey}/experiments/{experimentKey}`
- Documented the optional `rollup` query parameter on `POST /api/v2/auditlog`. Set it to `1` to return rolled-up audit log entries, which group related changes into one entry. The parameter already existed and its behavior is unchanged, but it was previously left out of the spec.
- Added a `sort` query parameter to `GET /api/v2/projects/{projectKey}/ai-configs/skills`. Use `sort=usedIn` to order agent skills by the number of AgentControl configs that use them, fewest first, or `sort=-usedIn` for most first. Without `sort`, skills are still ordered by creation date, newest first.

### Fixed

- Fixed the `next` link in `GET /api/v2/auditlog`, `POST /api/v2/auditlog` and the `REPORT` form of `/api/v2/auditlog` dropping `rollup`. When a request sets `rollup=1`, its `next` link now includes `rollup=1`, so later pages are rolled up like the first page. Previously only the first page was rolled up.

## [25.1.1] - 2026-10-28

### Added

- Added an optional `purpose` query parameter to `GET /api/v2/projects/{projectKey}/environments/{environmentKey}/sdk-active`. Set `purpose` to `ai` to check for AI SDK activity instead of any SDK. Any other value, or none, keeps the existing behavior.

## [25.1.0] - 2026-10-27

### Added

- Added optional `judgeScores` to AgentControl config metrics. It lists the average score and sample count for every judge metric recorded in the time range, keyed by the judge's evaluation metric key (`$ld:ai:judge:<suffix>`), including custom judges and the built-in accuracy, relevance, and toxicity judges. It is omitted when no judge scores were recorded. The existing `judgeAccuracy`, `judgeRelevance`, and `judgeToxicity` fields are unchanged. Affected endpoints:
  - `GET /api/v2/projects/{projectKey}/ai-configs/{configKey}/metrics`
  - `GET /api/v2/projects/{projectKey}/ai-configs/{configKey}/metrics-by-variation`
- Added optional `analysisUnit` on each metric in environment release responses. It is the context kind used as the metric's analysis unit. It is the release's randomization unit unless the metric uses a decoupled unit of analysis. Releases started before analysis units were recorded omit `analysisUnit`, and those metrics are analyzed on the randomization unit. Affected endpoints:
  - `GET /api/v2/projects/{projectKey}/flags/{flagKey}/environments/{environmentKey}/releases`
  - `POST /api/v2/projects/{projectKey}/flags/{flagKey}/environments/{environmentKey}/releases`
  - `GET /api/v2/projects/{projectKey}/flags/{flagKey}/environments/{environmentKey}/releases/{releaseId}`
  - `PUT /api/v2/projects/{projectKey}/flags/{flagKey}/environments/{environmentKey}/releases/{releaseId}/stop`
- Added optional `analysisUnit` on each metric in `POST /api/v2/projects/{projectKey}/flags/{flagKey}/environments/{environmentKey}/releases`. It sets the context kind used as the metric's analysis unit. Omit it to analyze on the randomization unit. A value must differ from the randomization unit and be one of the metric's units. Percentile metrics, ratio metrics, and metrics in a group cannot set it.

## [25.0.1] - 2026-10-26

_No gonfalon changelog entries. See the API changes in the release PR._
