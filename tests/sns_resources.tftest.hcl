# Test: SNS Topic Resource Translation
# LocalStack Compatibility: FULL
# Validates translation of CloudFormation SNS topics to Terraform aws_sns_topic resources
# These tests create SNS topic resources in LocalStack or AWS

provider "aws" {
  region = "us-east-1"

  # Skip AWS-specific validations when using LocalStack
  skip_credentials_validation = var.use_localstack
  skip_metadata_api_check     = var.use_localstack
  skip_requesting_account_id  = var.use_localstack

  # CRITICAL: LocalStack requires S3 path-style access
  s3_use_path_style = var.use_localstack

  # Dynamic endpoints - only populated when use_localstack = true
  dynamic "endpoints" {
    for_each = var.use_localstack ? [1] : []
    content {
      apigateway = var.localstack_endpoint
      dynamodb   = var.localstack_endpoint
      events     = var.localstack_endpoint
      iam        = var.localstack_endpoint
      lambda     = var.localstack_endpoint
      route53    = var.localstack_endpoint
      s3         = var.localstack_endpoint
      sns        = var.localstack_endpoint
      sqs        = var.localstack_endpoint
      sts        = var.localstack_endpoint
    }
  }
}

run "sns_topic_resources_created" {
  command = plan

  variables {
    config_path = "tests/fixtures/custom-resources-sns.yml"
  }

  # Verify SNS topic resources are created
  assert {
    condition     = length(aws_sns_topic.custom) == 2
    error_message = "Expected 2 SNS topic resources, got ${length(aws_sns_topic.custom)}"
  }

  # Verify AlertTopic resource exists
  assert {
    condition     = contains(keys(aws_sns_topic.custom), "AlertTopic")
    error_message = "AlertTopic resource not created"
  }

  # Verify EventTopic resource exists
  assert {
    condition     = contains(keys(aws_sns_topic.custom), "EventTopic")
    error_message = "EventTopic resource not created"
  }
}

run "sns_topic_properties_translated" {
  command = plan

  variables {
    config_path = "tests/fixtures/custom-resources-sns.yml"
  }

  # Verify AlertTopic name
  assert {
    condition     = aws_sns_topic.custom["AlertTopic"].name == "alert-topic-dev"
    error_message = "AlertTopic name not translated correctly"
  }

  # Verify AlertTopic display name
  assert {
    condition     = aws_sns_topic.custom["AlertTopic"].display_name == "Alert Notifications"
    error_message = "AlertTopic display_name not translated correctly"
  }

  # Verify EventTopic FIFO configuration
  assert {
    condition     = aws_sns_topic.custom["EventTopic"].fifo_topic == true
    error_message = "EventTopic fifo_topic not translated correctly"
  }

  # Verify EventTopic content-based deduplication
  assert {
    condition     = aws_sns_topic.custom["EventTopic"].content_based_deduplication == true
    error_message = "EventTopic content_based_deduplication not translated correctly"
  }
}

run "sns_topic_tags" {
  command = plan

  variables {
    config_path = "tests/fixtures/custom-resources-sns.yml"
  }

  # Verify tags are added
  assert {
    condition     = aws_sns_topic.custom["AlertTopic"].tags["Name"] == "AlertTopic"
    error_message = "AlertTopic Name tag not set correctly"
  }

  assert {
    condition     = aws_sns_topic.custom["AlertTopic"].tags["ManagedBy"] == "sls.tf"
    error_message = "AlertTopic ManagedBy tag not set correctly"
  }

  assert {
    condition     = aws_sns_topic.custom["AlertTopic"].tags["LogicalId"] == "AlertTopic"
    error_message = "AlertTopic LogicalId tag not set correctly"
  }
}
