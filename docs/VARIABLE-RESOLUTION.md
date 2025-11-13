# Variable Resolution Guide

This guide explains how to use Serverless Framework variable syntax in your `serverless.yml` configurations with the Terraform module.

## Overview

The module supports Serverless Framework variable resolution, allowing you to use dynamic references and environment variables in your configurations:

- `${self:property.path}` - Reference other properties in the same config
- `${env:VARIABLE_NAME}` - Environment variables
- `${env:VAR, 'default'}` - Environment variables with default values

## Supported Variable Types

### ${self:} - Internal References

Reference other properties within your serverless.yml configuration.

**Example:**
```yaml
service: my-service

provider:
  name: aws
  stage: ${self:custom.defaultStage}
  region: us-east-1

custom:
  defaultStage: dev
  bucketName: ${self:service}-${self:provider.stage}-bucket

functions:
  api:
    handler: handler.main
    environment:
      BUCKET_NAME: ${self:custom.bucketName}
```

**Terraform Usage:**
```hcl
module "serverless" {
  source = "./path/to/module"

  config_path = "${path.module}/serverless.yml"
}
```

The module automatically resolves `${self:custom.defaultStage}` to `"dev"` and `${self:custom.bucketName}` to `"my-service-dev-bucket"`.

### ${env:} - Environment Variables

Reference environment variables with optional default values.

**Example:**
```yaml
service: my-service

provider:
  name: aws
  stage: ${env:STAGE}
  region: ${env:AWS_REGION, 'us-east-1'}

functions:
  api:
    handler: handler.main
    environment:
      NODE_ENV: ${env:NODE_ENV}
      API_KEY: ${env:API_KEY, 'default-key'}
```

**Terraform Usage:**
```hcl
module "serverless" {
  source = "./path/to/module"

  config_path = "${path.module}/serverless.yml"

  environment_vars = {
    STAGE      = "production"
    AWS_REGION = "us-west-2"
    NODE_ENV   = "production"
    API_KEY    = var.api_key  # From Terraform variable
  }
}
```

## Configuration Options

### environment_vars

Map of environment variable names to values for `${env:}` resolution.

```hcl
variable "api_key" {
  description = "API key for external service"
  type        = string
  sensitive   = true
}

module "serverless" {
  source = "./path/to/module"

  config_path = "${path.module}/serverless.yml"

  environment_vars = {
    STAGE    = "production"
    API_KEY  = var.api_key
    NODE_ENV = "production"
  }
}
```

### strict_variable_resolution

Control error handling for unresolved variables (default: `true`).

```hcl
module "serverless" {
  source = "./path/to/module"

  config_path = "${path.module}/serverless.yml"

  # Fail on any unresolved variables (default)
  strict_variable_resolution = true

  environment_vars = {
    STAGE = "dev"
  }
}
```

**Strict Mode (true):**
- Terraform plan fails if any variable cannot be resolved
- Clear error messages show which variables are missing
- Recommended for production deployments

**Non-Strict Mode (false):**
- Unresolved variables remain as `${...}` syntax
- Useful for partial configurations or testing
- May cause errors in resource creation

### max_variable_depth

Maximum depth for recursive variable resolution (default: `10`).

```hcl
module "serverless" {
  source = "./path/to/module"

  config_path = "${path.module}/serverless.yml"

  # Limit recursion depth (prevents infinite loops)
  max_variable_depth = 5
}
```

## Examples

### Basic Self-Reference

```yaml
service: api-service

custom:
  stage: ${self:provider.stage}
  tableName: ${self:service}-${self:custom.stage}-table

provider:
  name: aws
  stage: dev
```

**Result:**
- `custom.stage` resolves to `"dev"`
- `custom.tableName` resolves to `"api-service-dev-table"`

### Environment Variables with Defaults

```yaml
provider:
  name: aws
  stage: ${env:DEPLOY_STAGE, 'dev'}
  region: ${env:AWS_REGION, 'us-east-1'}
```

**Terraform:**
```hcl
module "serverless" {
  source = "./path/to/module"

  config_path = "${path.module}/serverless.yml"

  # If DEPLOY_STAGE not provided, uses default 'dev'
  environment_vars = {
    AWS_REGION = "us-west-2"
  }
}
```

### Mixed Variables

```yaml
service: ${env:SERVICE_NAME, 'my-service'}

custom:
  bucketName: ${self:service}-bucket-${env:ENVIRONMENT}

provider:
  name: aws
  stage: ${env:STAGE}

functions:
  processor:
    handler: index.handler
    environment:
      BUCKET: ${self:custom.bucketName}
      STAGE: ${self:provider.stage}
```

## Error Handling

### Missing Required Variables

**Error:**
```
Error: Unresolved variable in 'provider.stage': ${env:STAGE}
```

**Solution:**
```hcl
module "serverless" {
  environment_vars = {
    STAGE = "production"  # Add missing variable
  }
}
```

### Circular References

Variables cannot reference themselves (directly or indirectly).

**Invalid:**
```yaml
custom:
  a: ${self:custom.b}
  b: ${self:custom.a}  # Circular!
```

**Error:** Would cause infinite loop (prevented by max_variable_depth)

## Best Practices

### 1. Use Defaults for Optional Variables

```yaml
provider:
  region: ${env:AWS_REGION, 'us-east-1'}  # Fallback to us-east-1
```

### 2. Keep Variable Paths Simple

```yaml
# Good: Simple, clear paths
stage: ${self:provider.stage}

# Avoid: Deeply nested paths
value: ${self:custom.nested.deep.value.here}
```

### 3. Use Terraform Variables for Secrets

```hcl
variable "database_password" {
  type      = string
  sensitive = true
}

module "serverless" {
  environment_vars = {
    DB_PASSWORD = var.database_password
  }
}
```

### 4. Enable Strict Mode in Production

```hcl
module "serverless" {
  strict_variable_resolution = true  # Catch missing variables early
}
```

### 5. Document Required Variables

```yaml
# serverless.yml
# Required environment variables:
# - STAGE: Deployment stage (dev/staging/production)
# - API_KEY: External API authentication key
# - AWS_REGION: AWS region for deployment

provider:
  stage: ${env:STAGE}
  region: ${env:AWS_REGION}
```

## Limitations (Phase 1)

The following variable types are not yet supported:

- `${opt:option}` - CLI options (Planned for Phase 2)
- `${cf:stack.output}` - CloudFormation outputs (Planned for Phase 2)
- `${ssm:/path/param}` - SSM parameters (Planned for Phase 2)
- `${file(./path.json):key}` - External file references (Planned for Phase 3)

For these cases, use Terraform data sources or variables directly.

## Troubleshooting

### Variables Not Resolving

1. **Check variable syntax:** Must be exactly `${type:reference}`
2. **Verify environment_vars:** Ensure all required vars are provided
3. **Check strict mode:** Try `strict_variable_resolution = false` for debugging
4. **Review error messages:** Terraform plan shows which variables failed

### Performance Issues

If resolution is slow:

1. **Reduce max_variable_depth:** Lower from default 10
2. **Simplify variable chains:** Avoid deeply nested references
3. **Use direct values:** Replace variables with actual values where possible

### Validation Errors After Resolution

Resolution happens before validation. If you get validation errors:

1. **Check resolved values:** Use `terraform console` to inspect `local.resolved_config`
2. **Verify defaults:** Ensure default values are valid
3. **Review variable types:** Ensure resolved values match expected types

## Advanced Usage

### Conditional Variables

```yaml
custom:
  isProd: ${env:STAGE, 'dev'} == 'production'
  # Note: Use Terraform conditionals instead for complex logic
```

### Dynamic Resource Names

```yaml
custom:
  tableName: ${self:service}-${self:provider.stage}-table

resources:
  Resources:
    MyTable:
      Type: AWS::DynamoDB::Table
      Properties:
        TableName: ${self:custom.tableName}
```

### Multi-Stage Deployments

```hcl
variable "stage" {
  type = string
}

module "serverless" {
  source = "./path/to/module"

  config_path = "${path.module}/serverless.yml"

  environment_vars = {
    STAGE = var.stage
  }
}
```

Deploy to different stages:
```bash
terraform apply -var="stage=dev"
terraform apply -var="stage=staging"
terraform apply -var="stage=production"
```

## See Also

- [Serverless Framework Variables Documentation](https://www.serverless.com/framework/docs/providers/aws/guide/variables)
- [Module README](../README.md)
- [Contributing Guide](../docs/CONTRIBUTING-GENERATED-CODE.md)
