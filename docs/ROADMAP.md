# Roadmap: gaps found evaluating a real consumer migration

> **Status 2026-07-24, layer 1 (v0.6.0): all 6 original gaps implemented.**
>
> 1. Athena — `AWS::Glue::Database` / `AWS::Athena::WorkGroup` (incl. per-workgroup
>    result config for a curated CTAS workgroup) / `AWS::Athena::NamedQuery`
>    (athena.tf, tests/athena_resources.tftest.hcl)
> 2. CloudWatch — `AWS::CloudWatch::Dashboard` + `AWS::CloudWatch::Alarm`
>    (cloudwatch-observability.tf, tests/cloudwatch_observability.tftest.hcl)
> 3. Alerting — alarm/OK/insufficient-data actions resolve `Ref`s to template SNS
>    topics; `AWS::SNS::Subscription` (https endpoint = PagerDuty-style secret-backed
>    integration) (cloudwatch-observability.tf)
> 4. Custom domain — SAM HttpApi `Domain` property: apigatewayv2 domain name +
>    per-BasePath API mappings + Route53 alias (http-api-domain.tf,
>    tests/sam_httpapi_domain.tftest.hcl)
> 5. Direct API GW → EventBridge — raw `AWS::ApiGatewayV2::Integration` with
>    `IntegrationSubtype: EventBridge-PutEvents` + `Route` on a self HttpApi;
>    RequestParameters is the transform; auto-created PutEvents credentials role;
>    an API with only direct routes is still created (http-api-v2-direct.tf,
>    tests/sam_httpapi_direct.tftest.hcl)
> 6. Multi-target rules — `AWS::Events::Rule` with a Targets list (lambda targets,
>    per-target DLQ via `Fn::GetAtt` to template queues, per-target retry policy)
>    (events-rules-cfn.tf, tests/events_rules_multi_target.tftest.hcl)
>
> **But layer 1 closing didn't produce a zero-diff migration.** Built the full
> `template.yaml` for the same consumer against v0.6.0 (tag `a96e7a7`,
> `terraform validate` clean) and found each "closed" gap has a real edge the
> commit message doesn't mention, plus one entirely new hole and one
> cross-cutting landmine that hits the resources that supposedly had **no**
> gap at all. See "Layer 2" below — that's what actually blocks zero-diff now.

Source: evaluating whether Texecom's `event-service` repo could migrate its
custom `infrastructure.yaml` (consumed by an in-house `elemental-event-driven-service`
Terraform module) to sls.tf, with the goal of a zero-diff `terraform plan`.
Verdict: **not possible as a full swap** — the gaps below all lack an sls.tf
equivalent today. A partial migration (Lambdas + DynamoDB + SQS/DLQs only,
scoped via `resource_types`) is feasible and would be zero-diff for that slice.

## Gaps (no sls.tf equivalent today)

### 1. Athena
No `AWS::Athena::*` support at all — database, workgroups (including a
"curated" workgroup with separate CTAS lifecycle/prefix config), or named SQL
views. `event-service` declares all of this (`athena:` block: database_name,
two workgroups, `raw_events_flattened` view, column schema for a nested
`sourcedetails` struct).

### 2. CloudWatch dashboards + alarms
No `AWS::CloudWatch::Dashboard` or `AWS::CloudWatch::Alarm` support. Consumer
declares a dashboard plus per-service alarm sets (lambda/api_gateway/dynamodb/
eventbridge/athena/s3/sqs) with configurable namespace, dimension, metrics,
period, statistic, threshold, comparison operator per resource class.

### 3. Alerting integrations (SNS-as-alarm-action, PagerDuty)
SNS topic *creation* is supported (`AWS::SNS::Topic`), but not wiring a topic
as a CloudWatch alarm action, nor a PagerDuty integration (secret-backed) on
top of it. Consumer also has an anomaly-detection toggle with no CFN/SAM
resource backing it — that's template-side config sls.tf has no hook for.

### 4. Custom domain for the API
No ACM cert / Route53 / API Gateway custom-domain-name wiring. Consumer sets
`api.custom_domain` (domain_name, hosted_zone, cert_arn) on top of the HTTP
API.

### 5. Direct API Gateway → service integration (non-Lambda)
sls.tf's HTTP API (`AWS::Serverless::HttpApi` self-created path) only wires
**Lambda** integrations per route. Consumer has a route
(`integration: eventbridge`) that integrates API Gateway directly to
EventBridge with no Lambda in the path (request template does the
transform). No equivalent — every HTTP event in sls.tf assumes a target
function.

### 6. Centrally-declared multi-target EventBridge rules
sls.tf wires EventBridge only via a function's own `EventBridgeRule` event —
one rule, one implicit target (that function). Consumer instead declares
rules centrally (`eventbridge.rules`), each with an arbitrary event pattern
and a list of targets (lambda + per-target DLQ + retry policy), so multiple
independently-configured targets can share one rule. Modeling this in SAM
would require one synthetic rule-owning resource per target, or a new
top-level construct — no clean per-function mapping today.

## What *does* map cleanly (no gap)

- Lambda functions + IAM roles
- DynamoDB tables (`AWS::DynamoDB::Table`)
- SQS queues / per-function DLQs
- Scheduled Lambda invocation (`Schedule` event) — covers the 30-min poll and
  the 5-min metric emitter
- SNS topic creation (not alarm-action wiring, see gap 3)

> **Status 2026-07-24, layer 2: gaps 7–11 implemented, tagged v0.7.0
> (`64a3bf1`), pushed to `origin/main`** — verified against current source,
> not just the commit message:
>
> 7. Function async/DLQ — SAM `DeadLetterQueue` → `dead_letter_config` on the
>    function (+ sqs:SendMessage/sns:Publish on the module-created role) and
>    `EventInvokeConfig` → `aws_lambda_function_event_invoke_config`; serverless
>    yaml `onError` / `maximumEventAge` / `maximumRetryAttempts` /
>    `destinations` (lambda-async.tf, tests/lambda_async_config.tftest.hcl)
> 8. Athena views — `AWS::Glue::Table` support incl. `TableType: VIRTUAL_VIEW` +
>    `ViewOriginalText` (presto-view encoding), the CFN-portable way to make
>    `raw_events_flattened` genuinely queryable; also covers nested-struct
>    column schemas (athena.tf, tests/athena_resources.tftest.hcl). Caveat:
>    ~~the module doesn't compute Athena's base64-encoded Presto view format
>    for you~~ **resolved 2026-07-24**: `TableInput.ViewSql` (sls.tf extension)
>    takes raw SQL and the module builds the presto-view envelope itself —
>    base64 JSON with originalSql/catalog/schema/Presto-typed columns
>    (string→varchar, struct<>→row(), int→integer etc.), defaults
>    `TableType: VIRTUAL_VIEW` and injects the `presto_view` parameter. A
>    hand-encoded `ViewOriginalText` still passes through verbatim. Template
>    authors write plain SQL again, as in the old `athena.views` block
>    (athena.tf, tests/athena_resources.tftest.hcl `view_sql_encoding`).
> 9. Dynamic alarm sets — top-level `alarms.groups` (yaml) /
>    `Metadata.SlsTf.Alarms` (SAM): `resource_names: []` expands to ALL created
>    resources of a class (lambda/dynamodb/sqs/sns/s3/eventbridge/athena), one
>    alarm per (group, metric, resource), tracking the resource set as it grows
>    (alarm-sets.tf, tests/alarm_sets.tftest.hcl)
> 10. Cert lifecycle — HttpApi `Domain` without `CertificateArn` but with
>    `Route53.HostedZoneId` self-provisions a DNS-validated ACM cert
>    (cert + validation record + validation waiter) (http-api-domain.tf)
> 11. Naming lint — `check "lambda_naming_convention"` warns when
>    `resource_types` is scoped and functions rely on generated names;
>    `functions_with_generated_names` output for pre-migration diffing;
>    `naming_convention_warning = false` to silence on greenfield
>    (naming-lint.tf, tests/naming_lint.tftest.hcl)
>
> Layer 3 dug into: found the gap-7 root-cause claim below was wrong (corrected
> in place), plus 2 new items (#12 DynamoDB access model, #13 no X-Ray) and
> confirmed IAM role tag/naming diffs + exact output-rewiring scope. A real
> `terraform plan` against the develop workspace is still not run — see
> "Layer 3" section for what was substituted and why.

## Layer 2: what v0.6.0 actually left open

Found by building the consumer's full template against v0.6.0 and reading the
new resource files line-by-line instead of trusting the changelog.

### 7. No function-level async invoke / DLQ config at all — the real blocker
Grepped every `.tf` in the module: zero `aws_lambda_function_event_invoke_config`,
zero `dead_letter_config` block on `aws_lambda_function` itself. SAM's own
`DeadLetterQueue` and `EventInvokeConfig` function properties (`dlq: {enabled,
name}` / `async: {max_age, retries}` in the consumer's per-function config) are
silently no-ops in this module — every one of the ~10 lambdas that declare them
would lose that config on migration. This is a bigger blocker than any of the
original 6: it's not a missing resource type, it's a missing *property* on the
one resource type everyone assumed was "done."
>
> **Correction (layer-3 pass):** the root-cause claim below this line in the
> original writeup was wrong. I checked `atp_heldoff_check`
> (`dlq: {enabled: false}` in the consumer's config) and saw a `null`
> `DeadLetterConfig`, then wrongly concluded the elemental module wires DLQ at
> the EventBridge-target level instead of the function level. Checking a
> lambda that actually has DLQ *on* — `atp_holdoff_disabled` — shows live
> `DeadLetterConfig.TargetArn` set and `EventInvokeConfig` matching
> `infrastructure.yaml` exactly (`MaximumRetryAttempts: 2`,
> `MaximumEventAgeInSeconds: 60`), confirmed against the elemental module's own
> source (`modules/lambda/main.tf:40-45,54-67`). The elemental module already
> does function-level DLQ/async config; the gap was purely "sls.tf v0.6.0 has
> no equivalent," not a semantic mismatch. v0.7.0's `lambda-async.tf` fix
> targets the right thing.

### 8. Athena "view" has no CFN primitive to begin with
`AWS::Athena::NamedQuery` (`athena.tf:89`) saves a query string you can run from
the console — it does not create `raw_events_flattened` as a queryable view
(`SELECT * FROM raw_events_flattened` would fail; you'd have to know to run the
named query instead). This isn't really an sls.tf oversight to fix with more
Terraform — CloudFormation has no native "create an Athena/Glue view" resource
at all. Closing this for real needs a Lambda-backed custom resource that runs
`CREATE OR REPLACE VIEW` DDL via the Athena API, which is a materially bigger
feature than a resource-type addition (custom-resource execution model, IAM for
Athena/Glue, drift handling if the view SQL changes). Flag as "needs a design
doc," not a follow-up PR.

### 9. Alarms need hand-enumeration; consumer configs them as a dynamic set
`cloudwatch-observability.tf:69` supports one alarm per declared resource, fine
for a fixed list. But the consumer's `alarm_metrics` groups (lambda, dynamodb,
etc.) use `resource_names: []` meaning "one alarm per module-derived resource,
whatever that set turns out to be" — ~25 alarms across 7 groups, sized by how
many lambdas/tables exist. There's no batch/templated alarm construct (a
`for_each`-over-something-dynamic SAM shape), so the template author has to
enumerate every alarm by hand and keep it in sync as lambdas are added/removed —
exactly the kind of drift the original config's `resource_names: []` was
designed to avoid.

### 10. Custom domain needs a pre-issued cert ARN — ACM/DNS validation stays external
`http-api-domain.tf:45` requires a literal `CertificateArn`; it does not create
or DNS-validate an ACM certificate. The consumer's `cert_arn: null` today means
the *elemental* module self-provisions the cert. Under sls.tf, cert issuance has
to be hand-written Terraform outside the SAM template, with the ARN threaded in
via `sam_template_parameters` — so "custom domain: closed" is true only for the
apigatewayv2 domain-name + mapping + Route53 alias part, not the cert lifecycle.

### 11. Lambda default naming convention doesn't match what's already deployed — hits the "no gap" bucket, not just the flagged ones
`main.tf:204`: when a function omits `name:`, sls.tf generates
`"${service}-${stage}-${key}"` (e.g. `events-develop-atp_heldoff_check`).
Checked live AWS for this exact consumer: the elemental module's actual deployed
names are `"${environment}-${service}-${key}"` — **reversed prefix order**
(`develop-events-atp_heldoff_check`, confirmed via `aws lambda list-functions`).
DynamoDB (`custom_resources.tf:82-85`) and SQS (`custom_resources.tf:209-210`)
both fall back to a generated name only when `TableName`/`QueueName` is omitted,
and a hand-written CFN template naturally sets those explicitly — so they dodge
this. Lambda is the one resource type in the "maps cleanly" list where a
SAM template author would plausibly *not* bother setting an explicit name,
because nothing in the SAM spec suggests you need to. Miss it here and
`terraform plan` doesn't show a diff — it shows a replace, on every lambda,
because the physical resource name changed. This is worth a lint/validation
warning in the module (e.g. "no `name:` set and `resource_types` includes
Function — verify this matches your existing naming convention") rather than
relying on template authors to know to check.

## Layer 3: verified against elemental module source + live AWS state

Dug into the three items flagged as "anticipated" above. Two panned out as
real, distinct gaps; the third resolved the gap-7 misdiagnosis (see
correction above) rather than adding a new one.

### 12. DynamoDB access is implicit-and-blanket in elemental, 100%-explicit in sls.tf
Elemental (`modules/lambda/locals.tf:29`): `db_access` defaults to `"read"` per
lambda if unset. `iam.tf:32-46` grants a policy scoped to
`var.dynamodb_table_arn_pattern` — a wildcard covering **every table in the
service**, not just tables that lambda touches. (This is why event-service's
`main.tf:383-405` needs an explicit `Deny` to claw back write access for
`panel_event_read` — the blanket grant is the thing being fought.) sls.tf
(`main.tf:174-192`) has no equivalent default: DynamoDB access is entirely
`iamRoleStatements`/`Policies:`, hand-written per function. Migrating means the
template author must manually reconstruct — table by table, function by
function — access elemental currently grants for free (and get the
wildcard-vs-scoped semantics right themselves, including re-deriving the
existing `panel_event_read` deny-write pattern from scratch).

### 13. No X-Ray tracing support at all — silent regression, not a diff
`grep -rn "tracing_config\|Tracing" *.tf` across the whole sls.tf source: zero
matches. `infrastructure.yaml:43` sets `xray_enabled: true` in
`defaults.lambda` — every lambda traces today. Migrating doesn't error and
doesn't show up as a `terraform plan` diff in the way a missing property
normally would (nothing to attach) — it just silently drops every lambda to
Lambda's default (`PassThrough`, tracing off). Distinct failure mode from the
rest of this doc: not a plan diff to catch, an observability regression that
ships quietly.

### IAM role: tags + naming, confirmed concretely
Elemental (`modules/lambda/iam.tf:12-17`): role name
`{env}-{service}-{key}-role`, trust policy is plain `lambda.amazonaws.com`,
**no tags on the role**. sls.tf v0.7.0 (`main.tf:124-192`): role name
`{service}-{stage}-{key}-role` (the gap-#11 naming-order landmine, confirmed to
extend to role names too, not just function names) **and does tag the role**
(`Service`/`Stage`/`Function`, `main.tf:145-149`). So even after fixing the
name order by hand, the role still diffs on tags every time.

### Output rewiring: confirmed exact shape, ~9 call sites
Elemental's `outputs.tf:23-32` gives a nested per-function object —
`lambda_functions[name] = {function_name, function_arn, role_name}` — and
`outputs.tf:49-60` gives `dynamodb_tables[name] = {table_name, table_arn,
table_id, stream_arn, ...}`. sls.tf's outputs are flat parallel maps
(`function_names`, `function_arns`, `role_names`,
`custom_dynamodb_table_names`, `custom_dynamodb_table_arns`), keyed by CFN
logical ID — casing likely needs reconciling too (elemental: snake_case keys;
CFN logical IDs conventionally PascalCase). Concretely, every one of these
event-service resources needs its module-output references rewritten:
`all_events_s3` (role_name), `panel_event_read_deny_write` (role_name + 2×
table_arn), `atp_record_count_metric_cloudwatch_put` (role_name),
`atp_heldoff_check_eventbridge_put` (role_name),
`receive_events_eventbridge_put` (role_name),
`check_arc_response_secretsmanager_get` (role_name), both schedule targets
(function_arn/function_name), and the `update_all_events_env` null_resource
(function_name + table_name). Mechanical, but real, and independent of
whether sls.tf has closed every resource-type gap.

### Real terraform plan: still not run
Time-boxed against it this pass — the local test suite alone timed out at
100s, and a full scratch `terraform plan` would cost more than the AWS
CLI field-level comparisons above delivered for items 7/12/13. Comparing
`aws lambda get-function-event-invoke-config` / `describe-table` /
`get-queue-attributes` output for a few representative resources against what
the module would produce was cheaper and caught the gap-7 misdiagnosis
directly — a full plan run is still the only way to catch further landmines
*systematically* rather than one at a time by inspection, and remains
un-run.

### Bottom line on "is it close"
Not fundamentally blocked — none of items 7–13 are "no amount of coverage
fixes this." X-Ray and DynamoDB-statement authoring are addressable feature
work; naming/tags are addressable by discipline (the new lint helps with one
half of that). But "close" undersells it: every layer closed has opened a
narrower one underneath it (6 → 5 new + 1 landmine → 3 new), and that pattern
hasn't broken yet.

## Layer 4: full infrastructure.yaml parity audit (2026-07-25)

> **Status 2026-07-25: gaps 14–28 all implemented** (suite at 334 passing):
> 14 PITR/TTL + 18 S3 lifecycle (custom_resources.tf); 15 `AWS::Events::EventBus`
> incl. rule EventBusName Refs (events-rules-cfn.tf); 16 tracing_config + X-Ray
> role policy, yaml `tracing`/`provider.tracing.lambda` + SAM `Tracing`/Globals
> (lambda-tracing.tf); 17 auto-created DLQs — function `dlq: {enabled, name}` /
> SAM `DeadLetterQueue.QueueName` and rule-target `DeadLetterConfig` without Arn
> auto-named `<rule>-<idx>` with EventBridge queue policy (lambda-async.tf,
> events-rules-cfn.tf); 19 scalar metric names + group-level snake_case
> settings + `dimension_key` aliases (alarm-sets.tf); 20 `StageName` + AWS_IAM
> route auth (http-api-v2-self.tf); 21 zone-by-name lookup, HostedZoneName or
> inferred from DomainName (http-api-domain.tf); 22 `EndpointSecretName`
> Secrets Manager endpoint (cloudwatch-observability.tf); 23 anomaly-detection
> alarms via `anomaly_detection: true` → ANOMALY_DETECTION_BAND metric-query
> pair (alarm-sets.tf); 24 generated dashboard from `dashboard: {name,
> services}` (dashboard.tf); 25 `Layers`/`KmsKeyArn`/yaml `layers`+`kmsKeyArn`
> (main.tf, sam-parser.tf); 26 `dbAccess`/`db_access: read|write` grants over
> template tables (lambda-db-access.tf); 27 `generated_name_order =
> "stage-service"` + `role_tags_enabled = false` (variables.tf, naming-lint.tf);
> 28 nested `lambda_functions` / `dynamodb_tables` outputs (outputs.tf).
> Consumer-shape integration test: tests/event_service_parity.tftest.hcl,
> driven by a condensed translation of the real infrastructure.yaml
> (tests/fixtures/event-service-parity.yml + sam-httpapi-parity.yaml). Also
> fixed en route: `{proxy+}` routes produced an invalid lambda-permission
> statement_id.
>
> Still required for the actual zero-diff verdict: run the swap against the
> consumer's develop workspace (Layer 3 "real plan" item — needs live state).

Mapped every block of the consumer's `infrastructure.yaml` against v0.7.1,
folding in the still-open layer-3 findings (#12 access model, #13 X-Ray, IAM
naming/tags, output shape). Target: a zero-change `terraform plan` against
`develop` when swapping the elemental module for sls.tf.

### 14. DynamoDB PITR + TTL
Every table sets `pitr_enabled: true` and `ttl: {enabled, attribute_name}`;
`aws_dynamodb_table.custom` maps neither `PointInTimeRecoverySpecification`
nor `TimeToLiveSpecification` — silent loss on all three tables (and PITR
disable would show as a diff on the swap).

### 15. Custom EventBridge bus creation
`eventbridge.bus_name: events-events-bus` (legacy `<env>-events-events-bus`
naming) creates a named bus. Rules can *target* a named bus but there is no
`AWS::Events::EventBus` support, so nothing creates it.

### 16. Lambda X-Ray tracing (= layer-3 #13)
`defaults.lambda.xray_enabled: true` applies to every function; no
`tracing_config` exists anywhere in the module (SAM `Tracing: Active` is
silently dropped), and module-created roles lack X-Ray write permissions.
Silent observability regression, not a plan diff.

### 17. Auto-created DLQs
`dlq: {enabled: true, name: x-dlq}` on functions and `dlq: {enabled: true}`
on rule targets auto-provision the queues (live queues `all_events_ingress-0..4`
confirm per-target auto-naming `<rule>-<idx>`). sls.tf only wires DLQs by
reference — ~10 queues would need hand-declaring.

### 18. S3 lifecycle configuration
`athena.curated.lifecycle_days: 1095` needs `LifecycleConfiguration` on
`AWS::S3::Bucket`; unmapped.

### 19. Alarm-set shape mismatch
Consumer groups put `period`/`statistic`/`threshold`/`comparison_operator`
(snake_case) and `dimension_key` at GROUP level with `metrics:` as a plain
name list; the v0.7.0 construct requires per-metric objects and camelCase.

### 20. Named API stage + AWS_IAM route auth
`stage_name: v1` (module only creates `$default`) and `authorization: AWS_IAM`
on a Lambda route (self-API routes only support CUSTOM/NONE).

### 21. Custom domain without a hosted zone ID
`custom_domain` gives `cert_arn: null` AND `hosted_zone_name: null` — the old
module infers the zone from the domain name. sls.tf requires an explicit
`Route53.HostedZoneId`; no zone lookup by name.

### 22. PagerDuty secret-backed endpoint
`pagerduty.integration.secret_name` sources the subscription endpoint from
Secrets Manager; sls.tf only accepts literal endpoints. (Disabled today —
would bite on enable.)

### 23. Anomaly detection
`anomaly_detection.enabled: true` needs anomaly-detection alarms
(threshold_metric_id + ANOMALY_DETECTION_BAND metric query); the alarm
mappings only model static thresholds.

### 24. Auto-generated dashboard
`monitoring.dashboard` with `extended_widgets` builds widget JSON from the
services list; sls.tf only passes through a hand-written DashboardBody.

### 25. Lambda layers + KMS encryption
`lambda_layers` / `encryption.kms_id` are null today, but neither `Layers`
nor function-level `KmsKeyArn` maps at all.

### 26. db_access-style DynamoDB grants (= layer-3 #12)
Elemental defaults every lambda to blanket `db_access: read` over ALL service
tables; sls.tf makes authors hand-write statements per function. Needs a
function-level `dbAccess: read|write` shorthand granting scoped statements
over the template's created tables (+ indexes), so migrating doesn't mean
re-deriving elemental's implicit grants by hand.

### 27. Generated-name order + role tag parity (= layer-3 IAM findings)
Elemental names are `{env}-{service}-{key}` (functions) and
`{env}-{service}-{key}-role` (roles, untagged); sls.tf generates
`{service}-{stage}-{key}` and tags roles. Needs a naming-order switch applied
consistently to generated function AND role names, plus a way to disable role
tags — otherwise every function and role replaces/diffs on the swap.

### 28. Elemental-shaped outputs
Consumer glue references `lambda_functions[x].{function_name, function_arn,
role_name}` and `dynamodb_tables[x].{table_name, table_arn, table_id,
stream_arn}` (~9 call sites). sls.tf outputs are flat parallel maps; add
nested per-resource output maps in the elemental shape to make the rewiring
near-mechanical.

### Out of module scope (recorded, not gaps to close here)
`npm_build_zip`/`zip_filename` (build pipeline → `lambda_code_source = "s3"`),
`api.docs` swagger hosting, vestigial RDS keys (`skip_final_snapshot`,
`engine_version`), and service-wide `tags:` injection (partially covered by
per-resource tags today).

## Layer 5: real `terraform import` + `plan` against live resources (2026-07-25, v0.8.0)

The layer-3 "real plan" item finally run — not against the real S3 backend
(swapping module source there just shows "destroy everything / create
everything" because Terraform addresses resources by path, which is a
Terraform artifact, not a real diff), but the correct version: a scratch root
with a **local** backend, sls.tf v0.8.0 (`da9e1ed`) sourced locally,
`generated_name_order = "stage-service"` + `role_tags_enabled = false` set,
explicit real resource names in the template to isolate remaining diffs from
the already-known naming issue — then `terraform import` of real live
resources by ARN/name, then `terraform plan` against that local state. This
is what actually answers "would swapping the module produce a clean plan,"
because import establishes the address mapping a real migration would need
anyway.

### 29. SQS default `message_retention_seconds` disagrees with elemental's default
Imported the real `develop-events-atp_holdoff_disabled-dlq-dlq` queue: live
`message_retention_seconds = 345600` (4 days, elemental's default). sls.tf's
`aws_sqs_queue` resource defaults to AWS's own default, `1209600` (14 days).
`infrastructure.yaml` never sets retention explicitly for any queue, so this
is two modules disagreeing on an unset default — a genuine non-zero `plan`
diff on the exact resource type gap 7/17 claimed to close.

### 30. sls.tf injects its own tag scheme unconditionally
Imported `aws_cloudwatch_event_bus.cfn["EventsBus"]` and
`aws_dynamodb_table.custom["AtpHoldoffStore"]`: both diff on tags. sls.tf adds
`LogicalId`/`Name`/`ManagedBy=sls.tf` to every resource it manages; elemental
tags with `ManagedBy=terraform`/`Terraform=true` instead, plus whatever
per-resource tags the consumer's config specifies (`Purpose`, `Feature`,
etc. — omitted from the scratch template this pass, so part of the observed
diff is a test-fixture gap, not attributable to sls.tf; the auto-injected
`ManagedBy=sls.tf`/`LogicalId`/`Name` triplet is the real, attributable
finding). `role_tags_enabled = false` (gap 27) only silences tags on IAM
roles — every other resource type still gets the sls.tf tag signature
unconditionally, so "zero-diff" fails on tags alone across the whole
resource set unless a broader tag-suppression knob exists.

### 31. Auto-generated DLQ names don't match live naming, even under gap 17's own convention
Live EventBridge target DLQ: `develop-events-eb-all_events_ingress-target-0-dlq`.
sls.tf v0.8.0's auto-DLQ-naming feature (gap 17, `<rule>-<idx>`) generates
`all_events_ingress-0` — no environment/service prefix, no `eb-` infix, no
`-dlq` suffix. Confirmed directly against live state, not inferred. The
function-level DLQ's live double-`-dlq` suffix (`...-dlq-dlq`) only matched
in this test because the scratch template hardcoded the literal string —
nothing in v0.8.0 derives that shape automatically either.

### 32. Structural: incremental `terraform import` is broken by the module's own for_each cross-references
The most consequential finding this pass. Importing one function's resources
without also importing every other function declared in the same template
fails outright — not with a diff, with a hard error. Reproduced twice:
`outputs.tf`'s `lambda_functions` output (`aws_lambda_function.functions[fn]`)
and `main.tf`'s `aws_iam_role_policy_attachment.lambda_logs`
(`aws_iam_role.lambda_execution[each.key].name`) both throw `Invalid index` /
"is object with 1 attribute" the moment state holds a strict subset of a
`for_each` resource set the template declares. Every function, every role,
every per-function attachment for a given resource type has to be imported
in one atomic batch before a single `plan` succeeds — there's no
resource-by-resource or function-by-function incremental path. That makes a
real brownfield cutover a single big-bang operation per resource type
(import all ~15 lambdas' roles/attachments together, or none), not the
"reconcile a few diffs at a time" migration the nested-output fix (gap 28)
was aiming to enable — and it's a direct side effect of that same for_each
pattern, not an unrelated bug.

### Bottom line
Not zero-diff. Confirmed real, attributable diffs (SQS retention default, tag
scheme) on resource types layers 1/2/4 each already claimed closed, confirmed
the auto-DLQ-naming gap directly against live state on the feature built
specifically to fix it, and surfaced a new structural problem — incremental
import doesn't work — that's more operationally important than any single
field diff, because it changes the shape of a real migration from
"reconcile as you go" to "all-or-nothing per resource type." Six layers in,
the pattern (closing gaps surfaces a sharper problem underneath) still hasn't
broken.

> **Status 2026-07-25 (later): layer 5 closed — the swap was actually run
> against develop.** Module fixes (suite at 335 passing):
>
> - #29 retention: auto-created DLQs now set `message_retention_seconds`
>   explicitly (var `auto_dlq_message_retention_seconds`, default 345600).
>   NOTE: re-checked every one of the 17 live queues — all are at 1209600, so
>   the original 345600-vs-1209600 finding did not reproduce; the knob exists
>   either way and the swap root pins 1209600.
> - #30 tags: `injected_tags_enabled = false` suppresses the sls.tf tag
>   signature on EVERY resource type (not just roles); `global_tags` applies a
>   custom signature; `AWS::Events::EventBus` now honors CFN `Tags`.
> - #31 naming: `function_dlq_name_template` / `target_dlq_name_template`
>   ("{prefix}-{name}-dlq" / "{prefix}-eb-{target_id}-dlq" reproduce the live
>   names exactly, verified against all 17 queues); plus
>   `function_dlq_policy_enabled = false` (incumbent inline policies stay),
>   `events_rule_permission_sid_template`
>   ("AllowExecutionFromEventBridge-{target_id}" matches live Sids), queue
>   policies now carry the live `AllowEventBridgeSendMessage` Sid, and
>   `schedule.name` pins schedule-rule names.
> - #32 import: nested outputs are try()-null-safe on partial state, and the
>   migration path is **import blocks in a single plan**, not incremental CLI
>   import — all 111 resources imported in ONE `terraform plan` with zero
>   errors, which dissolves the all-or-nothing problem (the plan computes
>   config against the full declared set, so partial-state indexing never
>   happens).
>
> **The actual run** (sls-swap/ scratch root in the event-service repo, local
> state, live develop account): 111 resources imported — 14 lambdas, 14 roles,
> 28 policy attachments, 14 event-invoke configs, 7 function DLQs, 6 target
> DLQs + queue policies, 6 rules + targets + lambda permissions, 3 DynamoDB
> tables (5-GSI schema, PITR, TTL), 1 event bus. Result:
> **0 to destroy, 0 real creates, 0 field diffs on any non-lambda resource.**
> Residual: the code-delivery triple (`filename`/`publish`/`source_code_hash`)
> on each lambda — Terraform-side deployment plumbing (scratch used stub
> code; `publish` is provider default normalization), not live-infrastructure
> drift — plus 15 local-only null_resource validators. Not yet modeled in the
> swap root: schedule rules (module now supports `schedule.name` but target
> id/retry parity is unverified), API Gateway, Athena/S3, monitoring
> alarms/dashboard — next iteration widens scope to those.

## Layer 6: config-format conversion (yaml → SAM), schedule rules, IAM grants (2026-07-25, v0.9.0)

The `sls-swap/` root had defaulted to `config_format = "yaml"` (Serverless
Framework native schema) by omission — inconsistent with this org's other
real sls.tf consumer (`env-initializer-lambdas`, explicit
`config_format = "sam"`). Converted it to a SAM `template.yaml` and widened
scope to the 2 schedule-triggered lambdas and the 6 hand-written IAM grants
that were previously entirely absent from the template. Final plan: **115 to
import, 23 to add (15 local validators + 6 new IAM grants + 2 pre-existing Sid
mismatches), 14 to change (pre-existing stub-zip artifact, unrelated), 0 to
destroy.**

### 33. SAM path silently computes wrong names without `Metadata.ServiceName` / `stage_override`
Serverless-Framework format gets service/stage from `service:`/`provider.stage:`
— SAM has neither field. Omit `Metadata: {ServiceName: ...}` and the module
defaults service to `"sam-service"` and stage to `"dev"`
(`sam-parser.tf:485`, `locals.tf:220`), silently computing every generated
name wrong (e.g. `dev-sam-service-all_events-role` instead of
`develop-events-all_events-role`). This doesn't error — `terraform plan`
just shows 14 IAM roles (and everything downstream) as **replace**, which
reads as "the config is wrong" when the real problem is a missing metadata
block. Needs a `check`/validation the naming-lint (gap 11) pattern already
established: warn when SAM format is used without `Metadata.ServiceName` set.

### 34. yaml→SAM conversion needs a logical-ID collision check
Serverless Framework keeps `functions:` and `resources:` in separate
namespaces — `atp_restore`, `atp_holdoff_disabled`, and `store_arc_response`
exist as both a function name and an EventBridge rule name today with no
conflict. SAM's `Resources:` is one flat map; the same key twice is invalid.
Any yaml→SAM translation (hand or tooled) needs to detect and rename these
collisions — not an sls.tf bug, but a sharp edge in the conversion path this
org is actually taking.

### 35. SAM's native `Schedule` function-event drops `Name`/`Description`/`Enabled`
`sam-parser.tf:355-357` only extracts `Properties.Schedule` (the cron/rate
expression itself) for that event type — everything else on the property
bag is silently ignored, so a live rule's actual name
(`events-atp-heldoff-check-develop`) can't be pinned through that path.
Worked around by modeling both schedules as raw `AWS::Events::Rule` +
`Targets` (the same multi-target-rule construct from gap 6/`events-rules-cfn.tf`)
instead of SAM's dedicated `Schedule` event — which, as a side effect, also
carries full `RetryPolicy` support that the dedicated schedule-event path
(`event_sources.tf`) doesn't have at all. Both rules + targets imported with
**zero diff** once modeled this way. Worth documenting as the recommended
pattern rather than fixing the native `Schedule` event type, since the
workaround is strictly more capable.

### IAM grants: clean adds, but real structural mismatches found along the way
All 6 hand-transcribed grants added cleanly as new resources (no naming
collision — checked live first via `aws iam list-role-policies`). Two things
surfaced that aren't sls.tf's problem but are real migration risk: (1)
`all_events`'s live S3 grant is a **separate managed policy + attachment**,
not an inline policy like the other 5 — structurally different mechanism,
not just a different name; (2) `check_arc_response`'s role carries a
ClickOps-added policy (`CLICKOPS_check_arc_response_secrets`) that exists
**outside Terraform entirely** — untracked drift a real cutover would
silently inherit or silently miss depending on how the migration handles
existing-but-unmanaged policies on a role it's about to take over.

### Bottom line
Config-format conversion is viable but not mechanical — two silent-failure
modes (#33, #34) that a script or a careless hand-port would hit without
warning. Schedule and IAM-grant gaps both closed cleanly once modeled
correctly. Seven layers in, still no fundamental blocker found — but every
layer still surfaces something the previous one's "done" claim didn't
cover.

## Layer 6: full-estate SAM swap (2026-07-25)

Widened the develop swap to the ENTIRE estate and pivoted the config to SAM
(`application.yaml`, the org-standard format). Module additions: Schedule
event Name/Description (SAM-native) + TargetId/RetryPolicy/PermissionSid
(extensions); v1 REST parity knobs (`rest_api_name` / `rest_api_description` /
`rest_api_endpoint_type` / `rest_api_stage_name` /
`rest_api_redeployment_triggers_enabled` / `apigw_lambda_permissions_enabled`);
integration URIs use the real deploy region (SAM's translated provider region
was baked in before); `Metadata.SlsTf.CustomDomain` feeds the v1 custom-domain
module for SAM templates (+ typed-variable fix that silently dropped unknown
keys, `evaluateTargetHealth`, `s3_force_destroy`); Glue database tag map
extension; S3 lifecycle `AbortIncompleteMultipartUpload`; schedule permission
Sid template/override.

**Result (sls-swap/, `application.yaml`, local state): 240 resources imported
in one plan — 0 destroys, 0 real creates, 0 field diffs on everything except
the 14 lambdas' code-delivery triple.** Coverage now includes: 2 schedule
rules/targets/permissions (live names, bare target ids, retry policies), the
v1 REST API (resources, ANY methods, integrations, deployment, v1 stage, EDGE
custom domain + base path + Route53 alias), Glue database/raw_events (partition
projection)/raw_events_flattened view (verbatim presto text), both Athena
workgroups, both S3 buckets + lifecycle + tags, 88 alarms (verbatim), 7 SNS
monitoring topics, the event_monitoring dashboard (verbatim body), plus
everything from layer 5. Intentionally unmanaged (unimported, untouched):
the two direct APIGW→EventBridge v1 methods + their shared credentials role
(v1 direct integration remains a module gap — the v2 path has it, v1 doesn't)
and the consumer's bespoke per-route lambda-permission glue.
