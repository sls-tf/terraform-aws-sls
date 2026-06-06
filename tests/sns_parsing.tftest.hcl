# Test: SNS Topic Parsing
# LocalStack Compatibility: FULL
# Validates parsing of CloudFormation SNS topic resources from serverless.yml
# These are parsing tests that validate locals - no AWS resources created

mock_provider "aws" {}

run "sns_topic_parsing" {
  command = plan

  variables {
    config_path = "tests/fixtures/custom-resources-sns.yml"
  }

  # Verify SNS topics are parsed
  assert {
    condition     = length(local.sns_topics) == 2
    error_message = "Expected 2 SNS topics, got ${length(local.sns_topics)}"
  }

  # Verify AlertTopic is parsed
  assert {
    condition     = contains(keys(local.sns_topics), "AlertTopic")
    error_message = "AlertTopic not found in parsed SNS topics"
  }

  # Verify EventTopic is parsed
  assert {
    condition     = contains(keys(local.sns_topics), "EventTopic")
    error_message = "EventTopic not found in parsed SNS topics"
  }

  # Verify AlertTopic properties
  assert {
    condition     = local.sns_topics["AlertTopic"].Properties.TopicName == "alert-topic-dev"
    error_message = "AlertTopic name not parsed correctly"
  }

  # Verify EventTopic FIFO configuration
  assert {
    condition     = local.sns_topics["EventTopic"].Properties.FifoTopic == true
    error_message = "EventTopic FifoTopic property not parsed correctly"
  }
}

run "sns_topic_snake_case_conversion" {
  command = plan

  variables {
    config_path = "tests/fixtures/custom-resources-sns.yml"
  }

  # Verify snake_case conversion for AlertTopic
  assert {
    condition     = local.to_snake_case["AlertTopic"] == "alert_topic"
    error_message = "AlertTopic snake_case conversion failed: got ${local.to_snake_case["AlertTopic"]}"
  }

  # Verify snake_case conversion for EventTopic
  assert {
    condition     = local.to_snake_case["EventTopic"] == "event_topic"
    error_message = "EventTopic snake_case conversion failed: got ${local.to_snake_case["EventTopic"]}"
  }
}
