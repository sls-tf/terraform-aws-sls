# Test: HTTP API custom domain (AWS::Serverless::HttpApi Domain property)
# Domain name + per-BasePath API mappings + Route53 alias record.

mock_provider "aws" {}

run "domain_resources_created" {
  command = plan

  variables {
    config_path   = "tests/fixtures/sam-httpapi-domain.yaml"
    config_format = "sam"
  }

  assert {
    condition     = length(aws_apigatewayv2_domain_name.self) == 1
    error_message = "Expected 1 custom domain, got ${length(aws_apigatewayv2_domain_name.self)}"
  }

  assert {
    condition     = length(aws_apigatewayv2_api_mapping.self) == 2
    error_message = "Expected 2 API mappings (one per BasePath), got ${length(aws_apigatewayv2_api_mapping.self)}"
  }

  assert {
    condition     = length(aws_route53_record.self_httpapi) == 1
    error_message = "Expected 1 Route53 alias record, got ${length(aws_route53_record.self_httpapi)}"
  }
}

run "domain_properties" {
  command = plan

  variables {
    config_path   = "tests/fixtures/sam-httpapi-domain.yaml"
    config_format = "sam"
  }

  assert {
    condition     = aws_apigatewayv2_domain_name.self["HttpApi"].domain_name == "api.example.com"
    error_message = "Domain name not translated"
  }

  assert {
    condition     = aws_apigatewayv2_domain_name.self["HttpApi"].domain_name_configuration[0].certificate_arn == "arn:aws:acm:eu-west-1:123456789012:certificate/abc-123"
    error_message = "Certificate ARN not translated"
  }

  assert {
    condition     = aws_apigatewayv2_domain_name.self["HttpApi"].domain_name_configuration[0].endpoint_type == "REGIONAL"
    error_message = "HTTP API domains must be REGIONAL"
  }

  assert {
    condition     = aws_apigatewayv2_api_mapping.self["HttpApi-v1"].api_mapping_key == "v1"
    error_message = "v1 base path mapping not created"
  }

  assert {
    condition     = aws_apigatewayv2_api_mapping.self["HttpApi-v2"].api_mapping_key == "v2"
    error_message = "v2 base path mapping not created"
  }
}

run "route53_record_properties" {
  command = plan

  variables {
    config_path   = "tests/fixtures/sam-httpapi-domain.yaml"
    config_format = "sam"
  }

  assert {
    condition     = aws_route53_record.self_httpapi["HttpApi"].zone_id == "Z0123456789ABCDEFGHIJ"
    error_message = "Route53 record zone not translated"
  }

  assert {
    condition     = aws_route53_record.self_httpapi["HttpApi"].name == "api.example.com"
    error_message = "Route53 record name not translated"
  }

  assert {
    condition     = aws_route53_record.self_httpapi["HttpApi"].type == "A"
    error_message = "Route53 record should be an A alias"
  }
}
