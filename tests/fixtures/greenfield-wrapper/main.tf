// Greenfield repro wrapper: instantiates sls.tf the way identity-service /
// scheduler-service do on a fresh account — with sam_template_parameters values
// that are computed in the SAME plan (terraform_data.output is unknown at plan,
// standing in for aws_secretsmanager_secret.x.arn / aws_security_group.x.id).
variable "resource_types" {
  type    = list(string)
  default = null
}

resource "terraform_data" "secret_arn" {
  input = "arn:aws:secretsmanager:eu-west-1:111111111111:secret:fake-abc123"
}

resource "terraform_data" "sg_id" {
  input = "sg-0123456789abcdef0"
}

module "sls" {
  source = "../../.."

  config_path   = "${path.module}/../sam-greenfield-unknown.yaml"
  config_format = "sam"

  resource_types = var.resource_types

  sam_template_parameters = {
    RelaySecretArn        = terraform_data.secret_arn.output
    LambdaSecurityGroupId = terraform_data.sg_id.output
  }
}

# Plan-time-known structural facts, so the test can assert that for_each keys
# survived the unknown parameter (the values behind them may be unknown).
output "function_keys" {
  value = keys(module.sls.functions)
}

output "custom_resource_counts" {
  value = module.sls.custom_resources_count
}
