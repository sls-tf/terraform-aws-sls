# Example: SAM HttpApi events that attach to an EXISTING shared apigatewayv2
# (HTTP API), plus a REQUEST Lambda authorizer. The module emits
# aws_apigatewayv2_integration / _route / _authorizer and the matching Lambda
# permissions (see http-api-v2.tf) instead of a self-created v1 REST API.

module "serverless" {
  source = "../.."

  config_format    = "sam"
  config_path      = "${path.module}/template.yaml"
  lambda_code_path = path.module

  sam_template_parameters = {
    SharedHttpApiId = "abc123def4"
  }
}
