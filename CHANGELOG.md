# Changelog

All notable changes to this module are documented here. Versions follow semver
and are published as git tags (`vMAJOR.MINOR.PATCH`).

## v0.8.0

### Added

- **DynamoDB PITR + TTL** — `PointInTimeRecoverySpecification` and
  `TimeToLiveSpecification` map to `point_in_time_recovery`/`ttl`.
- **S3 lifecycle rules** — `LifecycleConfiguration.Rules` (expiration,
  prefix filters, noncurrent-version expiration, transitions).
- **`AWS::Events::EventBus`** — custom bus creation; rule `EventBusName`
  accepts a Ref/name of a template bus.
- **Lambda X-Ray tracing** — SAM `Tracing` (function + Globals) and yaml
  `tracing` / `provider.tracing.lambda` → `tracing_config`, plus the
  AWSXRayDaemonWriteAccess policy on module-created roles
  (`lambda-tracing.tf`).
- **Auto-created DLQs** — yaml `dlq: {enabled, name}` / SAM
  `DeadLetterQueue.QueueName` provision the function DLQ (default
  `<function>-dlq`); an `AWS::Events::Rule` target `DeadLetterConfig` without
  an Arn provisions a per-target queue named `<rule>-<idx>` with the
  EventBridge delivery policy.
- **Consumer-shaped alarm groups** — `metrics:` as plain name lists,
  group-level `period`/`statistic`/`threshold`/`comparison_operator`
  (camelCase or snake_case) and `dimension_key` aliases.
- **Anomaly-detection alarms** — `anomaly_detection: true` on a group/metric
  emits the ANOMALY_DETECTION_BAND metric-query pair with
  `threshold_metric_id`.
- **Auto-generated dashboard** — `dashboard: {name, services}` (yaml) /
  `Metadata.SlsTf.Dashboard` (SAM) builds per-class timeSeries widgets from
  the created resource set (`dashboard.tf`).
- **Named HTTP API stage + AWS_IAM auth** — SAM HttpApi `StageName`; an event
  `Auth.Authorizer` of `AWS_IAM` selects IAM route auth.
- **Hosted zone lookup by name** — `Domain.Route53.HostedZoneName`, or a zone
  inferred from `DomainName`, replaces the mandatory `HostedZoneId`.
- **Secret-backed subscription endpoints** — `AWS::SNS::Subscription`
  `EndpointSecretName` fetches the endpoint (e.g. a PagerDuty URL) from
  Secrets Manager.
- **Lambda layers + KMS** — SAM `Layers`/`KmsKeyArn`, yaml
  `layers`/`kmsKeyArn`.
- **`db_access` grants** — function-level `dbAccess`/`db_access: read|write`
  grants the corresponding DynamoDB action set over all template tables and
  their indexes (`lambda-db-access.tf`).
- **Brownfield naming/tag parity** — `generated_name_order = "stage-service"`
  flips generated function/role/policy names to `<stage>-<service>-<key>`;
  `role_tags_enabled = false` leaves execution roles untagged.
- **Elemental-shaped outputs** — nested `lambda_functions`
  (`function_name`/`function_arn`/`role_name`) and `dynamodb_tables`
  (`table_name`/`table_arn`/`table_id`/`stream_arn`) maps.

### Fixed

- `{proxy+}` HTTP API routes produced an invalid character in the Lambda
  permission `statement_id`.

## v0.7.1

### Added

- **`TableInput.ViewSql` extension on `AWS::Glue::Table`** — declare an Athena
  view with raw SQL and the module computes the presto-view envelope
  (`/* Presto View: <base64 json> */` with originalSql/catalog/schema and
  Presto-typed columns: string→varchar, int→integer, struct<>→row()),
  defaulting `TableType: VIRTUAL_VIEW` and injecting the `presto_view`
  parameter. A hand-encoded `ViewOriginalText` still passes through verbatim.

## v0.7.0

### Added

- **Function-level async invoke + DLQ config** — SAM `DeadLetterQueue` maps to
  the function's own `dead_letter_config` (with `sqs:SendMessage`/`sns:Publish`
  granted to module-created roles) and `EventInvokeConfig` to
  `aws_lambda_function_event_invoke_config` (max event age, retries,
  on-success/on-failure destinations). Serverless yaml equivalents supported:
  `onError`, `maximumEventAge`, `maximumRetryAttempts`, `destinations`
  (`lambda-async.tf`).
- **`AWS::Glue::Table`** — full table support incl. nested-struct column
  schemas, storage/serde config, partition keys, and `TableType: VIRTUAL_VIEW`
  with `ViewOriginalText` (presto-view encoding), making Athena views
  first-class and queryable (`athena.tf`).
- **Dynamic alarm sets** — top-level `alarms:` (yaml) / `Metadata.SlsTf.Alarms`
  (SAM): alarm groups per resource class where `resource_names: []` expands to
  every created resource of that class; one alarm per (group, metric,
  resource) with class-default namespaces/dimensions and Ref-resolving actions
  (`alarm-sets.tf`).
- **Self-provisioned ACM certificates** — an HttpApi `Domain` with no
  `CertificateArn` but a `Route53.HostedZoneId` gets a DNS-validated ACM cert
  (certificate + validation record + validation waiter) wired into the domain
  (`http-api-domain.tf`).
- **Lambda naming-convention lint** — plan-time warning
  (`check "lambda_naming_convention"`) when a `resource_types` allowlist is in
  use and functions rely on generated `"<service>-<stage>-<key>"` names (a
  brownfield mismatch replaces the function); new
  `functions_with_generated_names` output for pre-migration diffing and
  `naming_convention_warning` variable to opt out (`naming-lint.tf`).

### Changed

- Alarm-action / SNS-subscription topic `Ref`s now resolve for topics excluded
  by the `resource_types` allowlist too, falling back to the deterministic ARN
  of the externally-owned topic.

## v0.6.0

### Added

- **Athena / Glue analytics resources** — `AWS::Glue::Database`,
  `AWS::Athena::WorkGroup` (incl. per-workgroup result configuration and
  `RecursiveDeleteOption`) and `AWS::Athena::NamedQuery`; `Ref`s to template
  databases/workgroups resolve to the created resources (`athena.tf`).
- **CloudWatch dashboards + alarms** — `AWS::CloudWatch::Dashboard` (string or
  object `DashboardBody`) and `AWS::CloudWatch::Alarm` with full metric
  configuration; alarm/OK/insufficient-data actions resolve `Ref`s to template
  SNS topics (`cloudwatch-observability.tf`).
- **SNS subscriptions** — `AWS::SNS::Subscription`, covering PagerDuty-style
  https endpoints and filter policies.
- **HTTP API custom domain** — the SAM `Domain` property on a self-created
  `AWS::Serverless::HttpApi`: apigatewayv2 domain name, one API mapping per
  `BasePath` entry, optional Route53 alias record (`http-api-domain.tf`).
- **Direct (non-Lambda) HTTP API integrations** — raw
  `AWS::ApiGatewayV2::Integration` with an `IntegrationSubtype`
  (e.g. `EventBridge-PutEvents`) plus its `Route`s on a self HttpApi;
  `RequestParameters` carries the transform; a minimal `events:PutEvents`
  credentials role is auto-created when none is declared; an API referenced only
  by direct routes is still created (`http-api-v2-direct.tf`).
- **Centrally-declared multi-target EventBridge rules** — `AWS::Events::Rule`
  with a `Targets` list: lambda targets, per-target dead-letter queues
  (`Fn::GetAtt` to template SQS queues) and per-target retry policies, with
  invoke permissions for lambda targets (`events-rules-cfn.tf`).

## v0.5.7

### Fixed

- **`resource_types = null` (the default) no longer errors on Terraform < 1.12.**
  Older Terraform does not short-circuit `||` inside validations and
  expressions, so every `var.resource_types == null || contains/length(...)`
  guard evaluated the right-hand side against `null` and failed with
  `Invalid function argument`. All guards are now null-safe:
  `contains(coalesce(var.resource_types, [X]), X)` at expression sites and a
  lazy ternary in the variable validation. Behaviour is unchanged on
  Terraform >= 1.12; on older versions the module now works as documented.

## v0.5.6

### Changed

- **Published to the Terraform Registry** as `sls-tf/sls/aws`. The repository was
  renamed to `terraform-aws-sls` to meet the registry's naming requirements.
- Added an Apache-2.0 `LICENSE` (required by the registry — earlier tags cannot
  be ingested as they predate it).
- Removed internal planning artifacts (`agent-os/`, working docs, conversion
  demo fixtures) from the tree and from git history.

## v0.5.5

### Fixed

- **Null-safety for the structure read.** On a preprocessor failure
  `sam_structure` now decodes an empty document (`{"Resources":{}}`) rather than
  resolving to `null`. The fallback is a JSON **string** fed to `jsondecode`, not
  an object literal — an object-literal fallback type-unifies with (and coerces)
  the real parsed structure on the success path, silently dropping every non-empty
  template to zero `Resources`. With the string fallback a failed read yields a
  clean empty module so the `config_validation` precondition (added in v0.5.4) is
  the single, specific thing that surfaces — and a valid template is untouched.

### Tests

- `valid_sam_has_no_preprocessor_errors` directly exercises
  `local.sam_preprocessor_errors`, guarding the new guard against false-firing on
  a healthy template; the loud-failure runs are retained as regression coverage.
  (The greenfield-defer path — where `sam_yaml` defers and only the structure read
  catches the error — fails on `module.sls`'s nested precondition, which
  `terraform test` cannot assert via `expect_failures`; it is verified manually.)

## v0.5.4

### Fixed

- Fail loudly on a SAM preprocessor error instead of silently producing a
  zero-resource module. `scripts/sam-preprocessor.js` returns `{content:"", error}`
  on a missing file, malformed YAML, an unresolved intrinsic in strict mode, or no
  `node` on PATH; that error was coalesced to `null` (`sam_structure`) or swallowed
  by `try()` (`sam_condition_params`). The existing validation only inspected the
  **resolved** read (`sam_yaml`), which **defers** on a greenfield/ephemeral plan
  that passes in-plan parameter values — so an error in the plan-known **structure**
  or **condition-params** reads (the ones that drive every `for_each` key) was
  missed, and the module produced zero Lambda functions with the failure only
  surfacing far downstream (e.g. an `aws_lambda_permission` "Function not found" in
  a consumer). A `config_validation` precondition now surfaces these reads' errors
  with the real preprocessor message at plan time.

## v0.5.3

### Added

- `structural_sam_parameters` variable: names of known-at-plan SAM Parameters
  (e.g. an environment suffix used in `!Sub` resource names/ARNs) that should be
  resolved in the **structural** parse, not just the parameters referenced by
  Conditions. Without this, when a caller's parameter value differs from the
  template Default, event sources and cross-resource references (S3 bucket names,
  SQS/DynamoDB stream ARNs) resolved against the Default and pointed at the wrong
  resource names. Default `[]` — fully backward compatible.

## v0.5.2

### Added

- Outputs for the v0.5.x resources so consumers can wire endpoints/ARNs:
  `http_api_ids`, `http_api_endpoints` (self-created HTTP API v2),
  `websocket_api_ids`, `websocket_api_endpoints`, `state_machine_arns`,
  `iam_role_arns`.

## v0.5.1

Additive, backward compatible. Builds on v0.5.0 so a SAM app that uses shared
IAM roles deploys as-is.

### Added

- **`AWS::IAM::Role` resources.** Created as `aws_iam_role` with the assume-role
  policy, inline `Policies` (→ `aws_iam_role_policy`), and `ManagedPolicyArns`
  (→ attachments). Role name = `RoleName` if set, else the logical ID — matching
  how the preprocessor fabricates `!GetAtt <Role>.Arn`, so references stay
  consistent. (`iam-roles.tf`)
- **Honor a function's explicit `Role`.** A Lambda with `Role:` no longer gets a
  module-created execution role; it uses the given role. A `Role` that
  `!GetAtt`/`!Ref`s a template `AWS::IAM::Role` binds directly to the created
  resource; an external ARN is used verbatim. Functions without `Role` are
  unchanged (per-function role from `Policies`).

### Fixed

- `s3_bucket_arns` output deduplicates buckets referenced by more than one S3
  event (previously a duplicate-map-key error).
- `s3_artefact_names` (S3 code source) handles `CodeUri: ./` (code at the
  template root) instead of failing on an empty path-segment list.
- Cross-resource function references (WebSocket IntegrationUri, authorizer
  FunctionArn) resolve when a parameter's caller value differs from its template
  Default — the function-name lookup now covers logical ID, resolved name, and
  structural (Default-resolved) name.

## v0.5.0

Adds full SAM-as-is support for HTTP-API/WebSocket/Step-Functions apps. All
changes are **additive and backward compatible** — existing consumers (e.g.
`env-initializer-lambdas` @ v0.3.18, the v2 attach-to-existing path) are
unaffected; the full v0.4.x test suite continues to pass unchanged.

### Added

- **Self-created HTTP API (v2).** An inline `AWS::Serverless::HttpApi` referenced
  by function events via `ApiId: !Ref <HttpApi>` is now created in full:
  `aws_apigatewayv2_api` (HTTP) + integrations + routes + a `$default`
  auto-deploy stage + CORS (from `CorsConfiguration`) + a REQUEST Lambda
  authorizer (from `Auth.Authorizers`). Previously such events were misrouted to
  the attach-to-existing path with an unresolved `ApiId`. (`http-api-v2-self.tf`)
- **WebSocket APIs.** `AWS::ApiGatewayV2::Api` with `ProtocolType: WEBSOCKET`,
  plus its `Route`/`Integration`/`Stage` sub-resources, become
  `aws_apigatewayv2_*` (WEBSOCKET) with Lambda invoke permissions.
  `AWS::ApiGatewayV2::Deployment` is subsumed by stage auto-deploy.
  (`websocket-api.tf`)
- **Step Functions.** `AWS::Serverless::StateMachine` /
  `AWS::StepFunctions::StateMachine` become `aws_sfn_state_machine` + execution
  role, with `DefinitionUri` rendered through `DefinitionSubstitutions` and
  `Policies` (LambdaInvokePolicy + inline statements) translated to the role.
  (`step-functions.tf`)
- **Standalone event source mappings.** A top-level
  `AWS::Lambda::EventSourceMapping` (e.g. a DynamoDB stream wired explicitly,
  rather than via a function `Events:` entry) now creates
  `aws_lambda_event_source_mapping`, mapping the source table's stream and target
  function back to the created resources. (`event-source-mappings-cfn.tf`)

### Fixed

- **Full-form CFN intrinsics.** The SAM preprocessor now evaluates the object
  form (`{ "Fn::Sub": … }`, `{ "Ref": … }`, `{ "Fn::GetAtt": … }`, …) in addition
  to the short tags (`!Sub`, `!Ref`, …). Templates mixing both forms — common in
  real SAM — now resolve correctly. (`scripts/sam-preprocessor.js`)
- **HttpApi authorizer name nesting.** The authorizer on an HttpApi event is now
  read from `Properties.Auth.Authorizer` (standard SAM) as well as
  `Properties.Authorizer`.
- **Authorizer function resolution.** An authorizer whose `FunctionArn` resolves
  to an explicit `FunctionName` (not the logical ID) now maps back to the correct
  function. (Both the attach and self paths.)
- **S3 event `Bucket: !Ref`.** An S3 event bucket given as `!Ref <Bucket>` now
  resolves to the bucket's real name instead of a marker string.
- **DynamoDB stream enablement.** A table whose `StreamSpecification` sets only
  `StreamViewType` (no `StreamEnabled`) now enables the stream, matching
  CloudFormation and avoiding the provider's stream_view_type/stream_enabled
  conflict.
- **Heterogeneous resource sets.** `sam_resources_translated` is laundered as a
  whole so templates mixing many resource shapes (ApiGatewayV2 + S3 + DynamoDB +
  …) no longer hit "inconsistent conditional result types".

### Notes for consumers

- New resource types are gated by the existing `resource_types` allowlist: when
  set, include `AWS::Serverless::HttpApi`, `AWS::ApiGatewayV2::Api`,
  `AWS::Serverless::StateMachine`, and `AWS::Lambda::EventSourceMapping` as
  needed. When `resource_types` is null (default) everything is created.
- State machine `DefinitionUri` files are read relative to `lambda_code_path`;
  ensure they are present alongside the Lambda code (symlink them in the
  consuming unit's `before_hook`, as with `lambdas/`).
