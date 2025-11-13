variable "domain_config" {
  description = "Custom domain configuration from provider.customDomain"
  type = object({
    domainName          = string
    basePath            = optional(string)
    stage               = optional(string)
    createRoute53Record = optional(bool)
    certificateArn      = optional(string)
    hostedZoneId        = optional(string)
    endpointType        = optional(string)
  })
  default = null
}

variable "api_gateway_rest_api" {
  description = "API Gateway REST API ID from roadmap #4 module"
  type        = string
}

variable "api_gateway_stage" {
  description = "API Gateway deployment stage name"
  type        = string
}

variable "create_hosted_zone" {
  description = "Create Route 53 hosted zone if hostedZoneId not provided"
  type        = bool
  default     = false
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN override (fallback if not in config)"
  type        = string
  default     = null

  validation {
    condition     = var.acm_certificate_arn == null || can(regex("^arn:aws:acm:[a-z0-9-]+:[0-9]+:certificate/[a-z0-9-]+$", var.acm_certificate_arn))
    error_message = "ACM certificate ARN must be a valid AWS ARN format: arn:aws:acm:region:account:certificate/id"
  }
}

variable "aws_region" {
  description = "AWS region for regional endpoint certificate validation"
  type        = string
}
