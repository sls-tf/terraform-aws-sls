# Changelog

All notable changes to this module are documented here. Versions follow semver
and are published as git tags (`vMAJOR.MINOR.PATCH`).

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
