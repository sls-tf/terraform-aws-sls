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
    condition     = var.resource_types == null || length(var.resource_types) > 0
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

variable "enable_custom_domain" {
  description = "Enable custom domain configuration for API Gateway (requires provider.customDomain block in serverless.yml)"
  type        = bool
  default     = false
}

variable "create_hosted_zone" {
  description = "Create Route 53 hosted zone if hostedZoneId not provided in customDomain configuration"
  type        = bool
  default     = false
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN for custom domain (fallback if not specified in customDomain.certificateArn)"
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
  type    = bool
  default = false
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
