variable "config_path" {
  description = "Path to the Serverless Framework configuration file (serverless.yml)"
  type        = string

  validation {
    condition     = var.config_path != ""
    error_message = "The config_path must be a non-empty string."
  }
}

variable "config_format" {
  description = "Format of the configuration file. Options: 'yaml' (serverless.yml), 'typescript' (serverless.ts), 'sam' (AWS SAM template.yaml)."
  type        = string
  default     = "yaml"

  validation {
    condition     = contains(["yaml", "typescript", "sam"], var.config_format)
    error_message = "The config_format must be 'yaml', 'typescript', or 'sam'."
  }
}

variable "sam_template_parameters" {
  description = "Parameter values for AWS SAM templates. Keys are parameter names as defined in the template Parameters section; values override the template Default."
  type        = map(string)
  default     = {}
}

variable "resource_types" {
  description = <<-EOT
    Allowlist of CloudFormation resource types to materialise from the resources: section.
    null (default) creates all supported resource types — preserves existing behaviour.
    Provide a list to restrict which infrastructure resources are created, letting the
    infrastructure team control what a service template is permitted to own in real AWS.

    Lambda functions, IAM roles, and all event wiring (API Gateway, S3 notifications,
    EventBridge rules, DynamoDB/SQS mappings) are always created regardless of this
    setting — it only gates standalone infrastructure from the resources: section.

    Example — Lambda only (SAM template used for sam local but infra managed elsewhere):
      resource_types = ["AWS::Serverless::Function"]

    Example — Lambda plus a tightly-coupled table:
      resource_types = ["AWS::Serverless::Function", "AWS::DynamoDB::Table"]
  EOT
  type        = list(string)
  default     = null

  validation {
    condition     = var.resource_types == null ? true : length(var.resource_types) > 0
    error_message = "resource_types must be null (all types) or a non-empty list."
  }
}

variable "aws_region" {
  description = "Optional AWS region override. If specified and differs from serverless.yml region, a warning will be displayed and this value will be used."
  type        = string
  default     = null
}

variable "lambda_code_path" {
  description = "Path to Lambda function code directory to package. Defaults to current directory. Ignored when var.lambda_code_source.type is \"s3\"."
  type        = string
  default     = "."

  validation {
    condition     = var.lambda_code_path != ""
    error_message = "lambda_code_path must not be an empty string."
  }
}

variable "lambda_code_source" {
  description = <<-EOT
    Where each function's deployment package is sourced from.

    type = "local" (default): build a zip from var.lambda_code_path (and the
    function's CodeUri sub-path) at apply time, using data.archive_file.

    type = "s3": treat the deployment package as already present in an S3
    bucket. Skip archive_file. Each function's S3 key is computed as
    "$${key_prefix}/$${artefact_name}/$${sha}.zip", where artefact_name is
    derived from the SAM template's CodeUri by stripping a trailing "dist/"
    segment and taking the last path component (e.g. "jobs/foo/dist/" -> "foo").
    Use this for git-ops deployment models where artefacts are built once in
    CI and promoted between environments by bumping the SHA pin.
  EOT
  type = object({
    type       = string
    bucket     = optional(string)
    key_prefix = optional(string)
    sha        = optional(string)
  })
  default = {
    type = "local"
  }

  validation {
    condition     = contains(["local", "s3"], var.lambda_code_source.type)
    error_message = "lambda_code_source.type must be \"local\" or \"s3\"."
  }

  validation {
    condition     = var.lambda_code_source.type != "s3" || (try(length(var.lambda_code_source.bucket), 0) > 0 && try(length(var.lambda_code_source.key_prefix), 0) > 0 && try(length(var.lambda_code_source.sha), 0) > 0)
    error_message = "lambda_code_source.{bucket, key_prefix, sha} are all required when type = \"s3\"."
  }
}

# enable_custom_domain and create_hosted_zone were REMOVED in v0.11.0.
#
# The custom domain is now enabled by the presence of its config
# (custom.slsTf.customDomain / Metadata.SlsTf.CustomDomain) like every other
# extension, and createHostedZone moved into that config. Removal rather than
# deprecation is deliberate: Terraform rejects unknown module arguments, so a
# caller still passing either one fails loudly instead of silently losing a
# setting. See docs/EXTENSIONS.md.

variable "acm_certificate_arn" {
  description = <<-DESC
    ACM certificate ARN for the custom domain, used when the config does not
    specify `customDomain.certificateArn`.

    This stays a module variable rather than moving into the extension config
    because it is frequently `aws_acm_certificate.this.arn` from the caller's
    own Terraform — a value no YAML file can name. That is the dividing line:
    config describing what the consumer wants belongs in the extension; wiring
    that can only come from Terraform stays a variable.
  DESC
  type        = string
  default     = null
}

# ============================================================================
# LocalStack Testing Configuration
# ============================================================================

variable "use_localstack" {
  description = "Enable LocalStack mode for testing. When true, all AWS provider endpoints will point to LocalStack."
  type        = bool
  default     = false
}

variable "localstack_endpoint" {
  description = "LocalStack endpoint URL. Only used when use_localstack is true."
  type        = string
  default     = "http://localhost:4566"

  validation {
    condition     = can(regex("^https?://", var.localstack_endpoint))
    error_message = "The localstack_endpoint must be a valid HTTP or HTTPS URL."
  }
}

# ============================================================================
# Variable Resolution Configuration
# ============================================================================

variable "environment_vars" {
  description = "Map of environment variables for $${env:} variable resolution. Keys are variable names, values are the resolved values."
  type        = map(string)
  default     = {}
}

variable "strict_variable_resolution" {
  description = "When true, fail on any unresolved variables. When false, allow unresolved variables to remain as-is."
  type        = bool
  default     = true
}

variable "max_variable_depth" {
  description = "Maximum depth for recursive variable resolution. Prevents infinite loops in circular references."
  type        = number
  default     = 10

  validation {
    condition     = var.max_variable_depth > 0 && var.max_variable_depth <= 50
    error_message = "max_variable_depth must be between 1 and 50."
  }
}

variable "strict_sam_intrinsics" {
  description = <<-DESC
    When true, unresolved CloudFormation intrinsic functions (!Ref, !Sub, !GetAtt
    etc.) that cannot be evaluated from the supplied parameters or the template's
    own resource definitions cause a clear plan-time error rather than producing
    placeholder marker strings. Defaults to false so that templates using
    !GetAtt for co-planned resources (whose real ARNs are only known post-apply)
    continue to work; enable it once all parameters are fully supplied and you
    want hard failure on any unresolvable reference.
  DESC
  type        = bool
  default     = false
}

variable "structural_sam_parameters" {
  description = <<-DESC
    Names of SAM template Parameters that are known at plan time AND affect
    resource STRUCTURE or names — e.g. an environment suffix used in !Sub
    resource names/ARNs (`Enviroment` -> `texecom-vv-videos-$${Enviroment}`).

    These are resolved in the structural (plan-time-known) parse, in addition to
    the parameters referenced by template Conditions, so that event sources and
    cross-resource references (S3 bucket names, SQS/DynamoDB ARNs, stream ARNs)
    resolve to the SAME names as the resolved resources. Without this, a caller
    value that differs from the template Default makes the structural parse use
    the Default — wiring then points at the wrong (Default-named) resources.

    Only list parameters whose values are ALWAYS known at plan (literals, SSM,
    remote state). Never list a parameter fed from an in-plan resource attribute
    (e.g. a co-planned ARN): that would defer the structural read and collapse
    every for_each key.
  DESC
  type        = list(string)
  default     = []
}

variable "stage_override" {
  description = <<-DESC
    Overrides the deployment "stage" used in every generated resource name
    (IAM roles, policies, log groups, event rules, function names, etc.), which
    otherwise defaults to the template's provider.stage or "dev". Set this to a
    per-environment value (e.g. an ephemeral PR-env slug) so multiple deployments
    of the same template can coexist in one account without name collisions.
    null = use the template/provider stage (unchanged behaviour).
  DESC
  type        = string
  default     = null
}

variable "extension_unknown_key_behaviour" {
  description = <<-DESC
    What to do about a key under the sls.tf extension namespace
    (`Metadata.SlsTf` / `custom.slsTf`) that this module version does not
    recognise, and about a misspelled namespace (`Metadata.Slstf`).

    `"error"` (default) fails the plan. Both cases are otherwise completely
    silent — a typo'd or too-new extension key produces a clean plan and no
    resources, which is the failure this module version exists to remove.

    `"warn"` downgrades both to a plan-time notice (check
    "extension_unknown_keys"), for rolling a large estate forward without a
    flag day. Defining one extension at two spellings is always an error and is
    not affected by this setting: there is no reading under which that config
    is correct.

    Only the sls.tf namespace is inspected, never its parent — `Metadata` and
    `custom:` legitimately carry other tools' config.
  DESC
  type        = string
  default     = "error"

  validation {
    condition     = contains(["error", "warn"], var.extension_unknown_key_behaviour)
    error_message = "extension_unknown_key_behaviour must be \"error\" or \"warn\", got: \"${var.extension_unknown_key_behaviour}\"."
  }
}

variable "extension_legacy_key_notice" {
  description = <<-DESC
    Emit a plan-time notice (check "extension_legacy_yaml_keys") when an
    extension is configured at its pre-v0.11.0 top-level serverless-yaml key
    (`alarms:`, `dashboard:`) rather than under `custom.slsTf`.

    Those keys are supported indefinitely — event-service parity is why alarm
    sets exist — so this is a signpost, not a deprecation clock. Set false to
    silence it if you have made a deliberate decision to stay on the top-level
    spelling.
  DESC
  type        = bool
  default     = true
}

variable "naming_convention_warning" {
  description = <<-DESC
    Emit a plan-time warning (check "lambda_naming_convention") when a
    resource_types allowlist is in use and any function omits an explicit
    name, since the module-generated "<service>-<stage>-<key>" name must match
    what is already deployed or the plan replaces the function. Set false to
    silence on greenfield deployments where generated names are fine.
  DESC
  type        = bool
  default     = true
}

variable "generated_name_order" {
  description = <<-DESC
    Order of the "<service>" and "<stage>" segments in every module-GENERATED
    resource name (functions, execution roles/policies, alarm-set lambda
    names). "service-stage" (default) yields "events-develop-fn";
    "stage-service" yields "develop-events-fn" — matching platform modules
    that prefix the environment first, so a brownfield swap keeps physical
    names. Explicit names are never affected.
  DESC
  type        = string
  default     = "service-stage"

  validation {
    condition     = contains(["service-stage", "stage-service"], var.generated_name_order)
    error_message = "generated_name_order must be \"service-stage\" or \"stage-service\"."
  }
}

variable "role_tags_enabled" {
  description = "Tag module-created Lambda execution roles (Service/Stage/Function). Set false for parity with platform modules that leave roles untagged — role tags otherwise diff on every plan after a brownfield swap."
  type        = bool
  default     = true
}

variable "injected_tags_enabled" {
  description = "Inject the module's tag scheme (Name/LogicalId/ManagedBy=sls.tf/Environment, and Service/Stage/Function on lambdas) on every managed resource. Set false for brownfield parity — only template-declared tags and var.global_tags are applied."
  type        = bool
  default     = true
}

variable "global_tags" {
  description = "Tags applied to every module-managed resource (after the injected scheme, so these win on conflict). Use to replicate an incumbent module's signature, e.g. { ManagedBy = \"terraform\" }."
  type        = map(string)
  default     = {}
}

variable "auto_dlq_message_retention_seconds" {
  description = "message_retention_seconds for AUTO-created DLQs (function dlq:{enabled} / rule-target DeadLetterConfig without Arn). Default 345600 (4 days) matches common platform-module defaults; AWS's own default is 1209600."
  type        = number
  default     = 345600
}

variable "function_dlq_name_template" {
  description = <<-DESC
    Name template for AUTO-created function DLQs. Placeholders: {prefix}
    (generated <service>-<stage> prefix per generated_name_order), {name}
    (the configured dlq name, or "<function>-dlq" when unset), {function}
    (the function key). Default "{name}" preserves existing behaviour;
    "{prefix}-{name}-dlq" replicates env-prefixed platform naming.
  DESC
  type        = string
  default     = "{name}"
}

variable "target_dlq_name_template" {
  description = <<-DESC
    Name template for AUTO-created EventBridge rule-target DLQs. Placeholders:
    {prefix}, {rule} (rule logical id), {index} (target index), {target_id}
    (the target's Id). Default "{rule}-{index}" preserves existing behaviour;
    "{prefix}-eb-{target_id}-dlq" replicates env-prefixed platform naming.
  DESC
  type        = string
  default     = "{rule}-{index}"
}

variable "function_dlq_policy_enabled" {
  description = "Create the module's dlq-access role policy for functions with a DLQ. Set false when the execution role already carries equivalent permissions (e.g. an incumbent module's inline policy that stays unmanaged through a migration)."
  type        = bool
  default     = true
}

variable "events_rule_permission_sid_template" {
  description = "statement_id template for the lambda permissions on AWS::Events::Rule targets. Placeholders: {key} (\"<rule>-<index>\"), {rule}, {index}, {target_id}. Default \"AllowEventsRuleInvoke-{key}\"; e.g. \"AllowExecutionFromEventBridge-{target_id}\" for parity with an incumbent module's Sids."
  type        = string
  default     = "AllowEventsRuleInvoke-{key}"
}

variable "schedule_permission_sid_template" {
  description = "statement_id template for schedule-event lambda permissions. Placeholders: {service}, {stage}, {function}, {index}. Default preserves the legacy \"<service>-<stage>-<function>-schedule-<index>\" form; e.g. \"AllowExecutionFromEventBridgeSchedule-{stage}\" for incumbent parity."
  type        = string
  default     = "{service}-{stage}-{function}-schedule-{index}"
}

variable "rest_api_name" {
  description = "Override for the v1 REST API name (default \"<service>-<stage>\"). For brownfield parity with an incumbent module's API name."
  type        = string
  default     = null
}

variable "rest_api_endpoint_type" {
  description = "Endpoint type for the v1 REST API: EDGE (default, legacy behaviour) or REGIONAL."
  type        = string
  default     = "EDGE"

  validation {
    condition     = contains(["EDGE", "REGIONAL", "PRIVATE"], var.rest_api_endpoint_type)
    error_message = "rest_api_endpoint_type must be EDGE, REGIONAL or PRIVATE."
  }
}

variable "rest_api_stage_name" {
  description = "Override for the v1 REST API stage name (default: the provider stage). e.g. \"v1\"."
  type        = string
  default     = null
}

variable "rest_api_redeployment_triggers_enabled" {
  description = "Recreate the API deployment when methods/integrations change (default true). Set false for brownfield import parity — an imported deployment has no trigger state, so the config triggers would force an immediate replace."
  type        = bool
  default     = true
}

variable "apigw_lambda_permissions_enabled" {
  description = "Emit the module's per-function API Gateway invoke permissions (default true). Set false when equivalent permissions already exist unmanaged (e.g. hand-written incumbent glue with bespoke statement ids)."
  type        = bool
  default     = true
}

variable "s3_force_destroy" {
  description = "force_destroy on module-managed S3 buckets (default true, legacy behaviour). Set false for brownfield parity — force_destroy is config-only, so an imported bucket diffs against true."
  type        = bool
  default     = true
}

variable "rest_api_description" {
  description = "Override for the v1 REST API description (default \"API Gateway for <service>\"). Set \"\" for parity with an incumbent API that has none."
  type        = string
  default     = null
}
