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
  description = "Path to Lambda function code directory to package. Defaults to current directory."
  type        = string
  default     = "."

  validation {
    condition     = var.lambda_code_path != ""
    error_message = "lambda_code_path must not be an empty string."
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
