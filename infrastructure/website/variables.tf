# ============================================================================
# Variables for sls.tf website infrastructure
# ============================================================================

variable "aws_region" {
  description = "AWS region for S3 bucket"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment (production or staging)"
  type        = string
  default     = "production"

  validation {
    condition     = contains(["production", "staging"], var.environment)
    error_message = "Environment must be either 'production' or 'staging'."
  }
}

variable "bucket_name" {
  description = "S3 bucket name for website hosting (must be globally unique)"
  type        = string
  default     = "sls-tf-website"
}
