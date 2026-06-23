# Full-app integration test: a single SAM template mixing every newly supported
# feature plus the existing ones. Mirrors the shape of the texecom
# video-verification template so it doubles as the "deploy the SAM as-is"
# acceptance test.

mock_provider "aws" {}

override_data {
  target = data.aws_region.current
  values = {
    region = "eu-west-2"
    name   = "eu-west-2"
  }
}

override_data {
  target = data.aws_caller_identity.current
  values = {
    account_id = "534294601285"
  }
}

run "full_app_plans_cleanly" {
  command = plan

  variables {
    config_path   = "tests/fixtures/sam-full-app.yaml"
    config_format = "sam"
  }

  # Self HTTP API + authorizer.
  assert {
    condition     = length(aws_apigatewayv2_api.self) == 1
    error_message = "Expected one self-created HTTP API."
  }
  assert {
    condition     = length(aws_apigatewayv2_authorizer.self) == 1
    error_message = "Expected the REQUEST authorizer."
  }

  # WebSocket API (separate from the HTTP API).
  assert {
    condition     = length(aws_apigatewayv2_api.websocket) == 1
    error_message = "Expected one WEBSOCKET API."
  }
  assert {
    condition     = aws_apigatewayv2_api.websocket["CommsWebSocket"].protocol_type == "WEBSOCKET"
    error_message = "WebSocket API must be WEBSOCKET protocol."
  }

  # Step Functions.
  assert {
    condition     = length(aws_sfn_state_machine.this) == 1
    error_message = "Expected one state machine."
  }

  # S3 bucket created and its event wired to the bucket's REAL name (the !Ref was
  # resolved, not left as a marker).
  assert {
    condition     = length(aws_s3_bucket.custom) == 1
    error_message = "Expected the VideosS3Bucket."
  }
  assert {
    condition     = contains(keys(aws_s3_bucket_notification.lambda_triggers), "texecom-vv-videos-dev")
    error_message = "S3 notification must key off the resolved bucket name (texecom-vv-videos-dev), proving the !Ref bucket resolved."
  }

  # DynamoDB table + its stream event source mapping.
  assert {
    condition     = length(aws_dynamodb_table.custom) == 1
    error_message = "Expected the VideoLog table."
  }
  # The SQS function event creates a mapping via the event path; the standalone
  # AWS::Lambda::EventSourceMapping (DynamoDB stream) creates one via the cfn path.
  assert {
    condition     = length(aws_lambda_event_source_mapping.event_sources) == 1
    error_message = "Expected one function-event source mapping (SQS)."
  }
  assert {
    condition     = length(aws_lambda_event_source_mapping.cfn) == 1
    error_message = "Expected one standalone EventSourceMapping (DynamoDB stream)."
  }

  # SQS queue + its event source mapping.
  assert {
    condition     = length(aws_sqs_queue.custom) == 1
    error_message = "Expected the PortalAPIQueue."
  }

  # Functions: APIAuth, GetVideos, ProcessRawVideo, ConnectMessage,
  # VideoLogStreamHandler, PortalQueueHandler, SaveStream = 7.
  assert {
    condition     = length(aws_lambda_function.functions) == 7
    error_message = "Expected seven Lambda functions."
  }

  # No unsupported-resource errors despite WebSocket sub-resources, StateMachine,
  # and Lambda::Permission resources in the template.
  assert {
    condition     = length(local.custom_resource_validation_errors) == 0
    error_message = "Full app must not raise unsupported-resource-type errors."
  }

  # Self HttpApi events must NOT create the v1 REST API.
  assert {
    condition     = length(aws_api_gateway_rest_api.this) == 0
    error_message = "Self HttpApi must not fall back to v1 REST."
  }
}
