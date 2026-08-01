# Changelog

All notable changes to this module are documented here. Versions follow semver
and are published as git tags (`vMAJOR.MINOR.PATCH`).

## v0.11.0

Extensions become a first-class concept — see
[docs/EXTENSIONS.md](docs/EXTENSIONS.md). Extensions are sls.tf-only config that
neither SAM nor Serverless Framework defines; they had arrived one at a time,
each with its own conventions, and every lookup was a bare `try()`. That made
"absent", "misspelled" and "not supported by this version" the same value — a
consumer pinned below the version that added alarm sets got a clean plan and
zero alarms.

**Read the Changed section before upgrading.** Configs using extensions only
through their documented keys are unaffected, but three module variables were
removed and one serverless-yaml key moved. A config that was silently doing
nothing will now fail loudly, which is the point of the release.

### Added

- **Extension registry** (`extensions.tf`) — the three extensions (`Alarms`,
  `Dashboard`, `CustomDomain`) are declared in one place with the parse each is
  read from, the version that introduced it, and its stability. Implementations
  resolve through `local.extension_config_json` rather than reaching into
  `local.sam_structure` / `local.sam_raw` directly.
- **`extensions_active` output** — extensions resolved from the config, keyed by
  name. An extension is active if and only if its config is present, so this is
  a plan-time answer to "did my extension config take effect?" instead of a
  deploy-and-check. Assertable in `terraform test`.
- **`module_version` output** and `local.module_version` (`version.tf`) — a
  module cannot read its own source ref at plan time, so the version is
  hand-maintained and asserted against the newest CHANGELOG heading by
  `make check-version`.
- **`custom.slsTf.*` serverless-yaml namespace** — mirrors `Metadata.SlsTf.*` by
  mechanism: `custom:` is the section Serverless Framework leaves unvalidated,
  as `Metadata` is the section CloudFormation ignores.
- **Unknown extension keys fail the plan** — a key under the sls.tf namespace
  this version doesn't recognise is now an error naming the key, the nearest
  match, the supported set and the running version. A misspelled *namespace*
  (`custom.slstf`, `Metadata.Slstf`) has its own check, since it would
  otherwise stay silent. `extension_unknown_key_behaviour = "warn"` downgrades
  both. Strictness is scoped to the sls.tf namespace, never `custom:` or
  `Metadata` at large.
- **`required_extensions`** — assert the extensions a config depends on. The one
  guard that works against an older module version: Terraform rejects unknown
  module arguments, so a version predating the extension fails with
  "Unsupported argument" instead of silently doing nothing. Also catches an
  extension that is implemented but whose config didn't resolve.
- **`extension_sidecar_path`** — hold extensions in a separate file
  (conventionally `slstf.yaml`) instead of inline, so the template stays
  pristine and `sam deploy` on it is honest about what it deploys rather than
  silently dropping inert vendor config. Same extension names and shapes,
  same unknown-key checking. The path is explicit rather than discovered by
  filename: a sidecar found by convention could be renamed and simply stop
  applying. Defining an extension both in the sidecar and inline is an error,
  and `extensions_active` reports `sidecar:<path>` as the source.
- **Structural-parse mismatch check** — warns when an extension read from the
  structural parse resolves differently there than in the resolved parse, which
  means a template Parameter is falling back to its `Default`. The fix it
  recommends (`structural_sam_parameters`) is verified by test to both clear the
  warning and route the alarm to the passed value.

### Changed

- **BREAKING: the serverless-yaml extension keys move under `custom.slsTf`,
  with no aliases.** `alarms:` -> `custom.slsTf.alarms`, `dashboard:` ->
  `custom.slsTf.dashboard`, `provider.customDomain` ->
  `custom.slsTf.customDomain`. Nothing had adopted the old spellings in a
  deployed configuration, so keeping them would have been compatibility with
  nobody at the cost of a permanently ambiguous namespace. A config still using
  one is a plan-time error naming the replacement — reading it, or ignoring it
  silently, would reproduce the failure this release removes.
- **BREAKING: `enable_custom_domain` removed.** It defaulted to `false` and was
  ANDed with the config, so a complete `customDomain` block with the flag unset
  created nothing and planned clean. Presence of the config now enables the
  domain, as it already did for every other extension. Removal rather than
  deprecation is deliberate: Terraform rejects unknown module arguments, so a
  caller still passing it fails loudly.
- **BREAKING: `create_hosted_zone` removed**, moving to
  `customDomain.createHostedZone` in the config. `acm_certificate_arn` stays a
  variable — it is frequently a co-planned `aws_acm_certificate.this.arn`, which
  no YAML file can name.

### Fixed

- **SAM alarm sets aborted the plan** whenever `Metadata.SlsTf.Alarms` was
  non-empty. The lookup encoded to JSON *outside* the conditional, leaving
  Terraform to unify the two branch types — and an object with attributes does
  not unify with `{}`:

  ```
  Error: Inconsistent conditional result types
    The 'true' value includes object attribute "defaults", which is absent in
    the 'false' value.
  ```

  Broken since alarm sets shipped in v0.7.0. No fixture used the SAM key —
  every alarm-set test went through the serverless-yaml path, whose empty value
  is `null` and therefore unifies — so it survived to v0.10.0 unnoticed.
  `tests/fixtures/sam-extensions.yaml` now covers the SAM branch.

## v0.10.0

Full-estate brownfield parity on SAM templates — verified by importing 240
live resources (lambdas, schedules, v1 REST API + custom domain, Glue/Athena,
S3, 88 alarms, SNS topics, dashboard) in a single plan with zero field diffs
outside the lambda code-delivery attributes.

### Added

- **Schedule event parity** — SAM Schedule `Name`/`Description` translate;
  `TargetId`, `RetryPolicy` and `PermissionSid` extensions (also serverless
  yaml `schedule.targetId`/`retryPolicy`/`permissionSid`);
  `schedule_permission_sid_template` variable.
- **v1 REST API parity knobs** — `rest_api_name`, `rest_api_description`,
  `rest_api_endpoint_type` (EDGE/REGIONAL/PRIVATE), `rest_api_stage_name`,
  `rest_api_redeployment_triggers_enabled`,
  `apigw_lambda_permissions_enabled`.
- **SAM custom domain** — `Metadata.SlsTf.CustomDomain` feeds the v1
  custom-domain module; `evaluateTargetHealth` supported on the Route53 alias.
- **`s3_force_destroy`** — disable the config-only force_destroy for import
  parity.
- **Glue database `Properties.Tags`** (map extension) and S3 lifecycle
  `AbortIncompleteMultipartUpload`.

### Fixed

- v1 REST Lambda integration URIs used the parsed provider region (a baked-in
  default for SAM templates) instead of the actual deploy region.
- The custom-domain module's typed `domain_config` silently dropped unknown
  keys.

## v0.9.0

Brownfield-parity release, driven by a real `terraform import` + `plan` of the
event-service develop environment (111 resources imported in one plan; zero
field diffs on every non-lambda resource).

### Added

- **`injected_tags_enabled`** — set false to suppress the module's tag
  signature (Name/LogicalId/ManagedBy=sls.tf, and Service/Stage/Function on
  lambdas) on EVERY resource type; **`global_tags`** applies a custom
  signature. `AWS::Events::EventBus` now also honors CFN `Tags`.
- **`auto_dlq_message_retention_seconds`** — explicit retention on
  auto-created DLQs so two modules can't disagree on an unset default.
- **`function_dlq_name_template` / `target_dlq_name_template`** — placeholder
  templates ({prefix}/{name}/{function}/{rule}/{index}/{target_id}) so
  auto-created DLQ names can match incumbent naming (e.g.
  "{prefix}-eb-{target_id}-dlq").
- **`function_dlq_policy_enabled`** — set false when the execution role
  already carries DLQ permissions from an incumbent module.
- **`events_rule_permission_sid_template`** — statement_id parity for rule
  target permissions (e.g. "AllowExecutionFromEventBridge-{target_id}").
- **`schedule.name`** — explicit schedule-rule names.
- Target-DLQ queue policies carry an `AllowEventBridgeSendMessage` Sid,
  matching common incumbent policies.

### Changed

- `publish` on functions is now null (provider default) instead of an
  explicit false, so imported functions don't diff on it.
- Nested `lambda_functions`/`dynamodb_tables` outputs are try()-null-safe and
  evaluate against partial state (mid-import).
- Documented migration path: import blocks in a single plan (all resources at
  once) rather than incremental CLI `terraform import`, which fails on
  partial for_each state.

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
