module "serverless" {
  source = "../.."

  config_path      = "${path.module}/serverless.yml"
  lambda_code_path = path.module
}
