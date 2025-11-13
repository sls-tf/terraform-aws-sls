# sls.tf - Serverless Framework YAML Parser for Terraform

A Terraform module that parses and validates Serverless Framework configuration files (serverless.yml), enabling you to use Serverless Framework syntax while deploying with Terraform.

## Features

### Configuration Parsing
- **Pure Terraform Implementation**: Uses native HCL functions (`yamldecode`, `file`, `try`, `coalesce`, `merge`)
- **Comprehensive Validation**: Validates against Serverless Framework schema with clear error messages
- **Error Collection**: Collects and displays all validation errors at once (not one-at-a-time)
- **Default Application**: Applies Serverless Framework defaults automatically
- **Function Inheritance**: Functions inherit provider-level defaults with override support
- **Strict Runtime Validation**: Enforces explicit runtime specification (no permissive defaults)
- **Functionless Support**: Validates infrastructure-only serverless.yml configurations
- **Region Override**: Supports region override with non-blocking warnings

### Lambda Function Translation
- **Automatic Lambda Provisioning**: Generates `aws_lambda_function` resources from serverless.yml
- **Code Packaging**: Automatically packages function code into ZIP files for deployment
- **IAM Role Creation**: Creates execution roles with CloudWatch Logs permissions for each function
- **Environment Variables**: Supports function-level environment variables
- **Multiple Runtimes**: Deploy functions with different runtimes in the same service
- **Change Detection**: Uses source code hashing for automatic redeployment on code changes

## Requirements

- Terraform >= 1.0.0
- AWS Provider >= 6.0
- Null Provider >= 3.0
- Archive Provider >= 2.0
- External Provider >= 2.0 (for TypeScript support)
- Node.js >= 14.0.0 (for TypeScript support)
- npm (for TypeScript support)

### TypeScript Support Requirements

If using TypeScript configuration files (`serverless.ts`):

```bash
# Install TypeScript parsing dependencies
cd /path/to/sls.tf/scripts
npm install
```

## Usage

### Lambda Function Deployment

```hcl
module "serverless" {
  source = "path/to/sls.tf"

  config_path      = "${path.module}/serverless.yml"
  lambda_code_path = "${path.module}"  # Directory containing your Lambda code
}

# Access deployed Lambda functions
output "function_arns" {
  value = module.serverless.function_arns
}

output "function_names" {
  value = module.serverless.function_names
}
```

### Configuration Parsing Only

If you only want to parse the configuration without deploying resources:

```hcl
module "serverless_parser" {
  source = "path/to/sls.tf"

  config_path = "${path.module}/serverless.yml"
}

output "service_name" {
  value = module.serverless_parser.service_name
}

output "functions" {
  value = module.serverless_parser.functions
}
```

### TypeScript Configuration Files

You can also use TypeScript configuration files (`serverless.ts`) for better type safety and developer experience:

```hcl
module "serverless_typescript" {
  source = "path/to/sls.tf"

  config_path    = "${path.module}/serverless.ts"
  config_format  = "typescript"
}

output "service_name" {
  value = module.serverless_typescript.service_name
}
```

#### Example TypeScript Configuration

```typescript
// serverless.ts
import { AwsProvider } from '@serverless/types/aws';

const serverlessConfiguration = {
  service: 'my-typescript-service',
  frameworkVersion: '3',

  provider: {
    name: 'aws',
    runtime: 'nodejs18.x',
    region: 'us-east-1',
    stage: 'dev',
    environment: {
      NODE_ENV: 'development'
    }
  },

  functions: {
    api: {
      handler: 'src/handlers/api.handler',
      description: 'API Gateway handler',
      memorySize: 512,
      timeout: 30,
      events: [
        {
          http: {
            path: '/api/{proxy+}',
            method: 'any',
            cors: true
          }
        }
      ]
    }
  },

  custom: {
    // Custom variables with TypeScript support
    deploymentTime: new Date().toISOString()
  }
};

export default serverlessConfiguration;
```

#### Advanced TypeScript Features

The module supports advanced TypeScript features:

**Async Exports:**
```typescript
// Async configuration loading
async function loadConfig() {
  // Load environment-specific settings
  const stage = process.env.NODE_ENV || 'dev';

  return {
    service: 'my-service',
    provider: {
      name: 'aws',
      stage
    }
  };
}

export default loadConfig;
```

**Dynamic Configuration:**
```typescript
// Dynamic values and imports
const packageJson = require('./package.json');

export default {
  service: 'my-service',
  provider: {
    name: 'aws',
    environment: {
      VERSION: packageJson.version
    }
  }
};
```

#### TypeScript Prerequisites

Make sure you have the required dependencies installed:

```bash
# In the module's scripts directory
cd path/to/sls.tf/scripts
npm install

# In your project directory (optional, for local testing)
npm install typescript ts-node
```

### Example serverless.yml

```yaml
service: my-service
frameworkVersion: '3'

provider:
  name: aws
  runtime: nodejs18.x
  region: us-east-1
  stage: dev
  memorySize: 1024
  timeout: 6

functions:
  hello:
    handler: handler.hello
    description: Hello function
    environment:
      TABLE_NAME: my-table

  world:
    handler: handler.world
    runtime: python3.9
    memorySize: 2048
    timeout: 30

custom:
  myValue: example

resources:
  Resources:
    MyBucket:
      Type: AWS::S3::Bucket
```

The module will automatically:
- Package your Lambda code into ZIP files
- Create IAM execution roles with CloudWatch Logs permissions
- Deploy Lambda functions with the specified configuration
- Apply environment variables to functions

## Input Variables

| Name | Type | Default | Required | Description |
|------|------|---------|----------|-------------|
| `config_path` | string | - | yes | Path to the Serverless Framework configuration file (serverless.yml or serverless.ts) |
| `config_format` | string | `"yaml"` | no | Format of the configuration file. Options: `"yaml"` or `"typescript"`. |
| `lambda_code_path` | string | `"."` | no | Path to Lambda function code directory to package. Defaults to current directory. |
| `aws_region` | string | `null` | no | Optional AWS region override. If set and differs from serverless.yml region, a warning will be displayed. |

## Outputs

### Configuration Outputs
| Name | Type | Description |
|------|------|-------------|
| `parsed_config` | object | Complete parsed Serverless Framework configuration |
| `service_name` | string | Service name extracted from configuration |
| `provider_config` | object | Provider configuration with defaults applied |
| `functions` | map(object) | Map of function definitions with defaults applied |
| `custom` | object | Custom configuration section (null if not present) |
| `resources` | object | Resources section for custom AWS resources (null if not present) |
| `package` | object | Packaging configuration (null if not present) |

### Lambda Function Outputs
| Name | Type | Description |
|------|------|-------------|
| `function_arns` | map(string) | Map of Lambda function ARNs keyed by function name |
| `function_names` | map(string) | Map of Lambda function names keyed by function name |
| `role_arns` | map(string) | Map of IAM role ARNs keyed by function name |
| `function_invoke_arns` | map(string) | Map of Lambda invoke ARNs for API Gateway integration |
| `lambda_packages` | map(object) | Lambda deployment package information (paths, sizes, hashes) |

## Validation Rules

### Required Fields
- `service`: Service name (non-empty string)
- `provider`: Provider configuration object
- `provider.name`: Must be `"aws"`
- `provider.runtime` OR per-function `runtime`: At least one must be specified (strict mode)
- `functions[].handler`: Required for each function

### Optional Field Validation
- `frameworkVersion`: Must be 2.x, 3.x, or 4.x if specified
- `provider.memorySize`: 128-10240 MB
- `provider.timeout`: 1-900 seconds
- `functions[].memorySize`: 128-10240 MB
- `functions[].timeout`: 1-900 seconds

### Default Values (Serverless Framework Specification)
- `provider.stage`: `"dev"`
- `provider.region`: `"us-east-1"` (or `var.aws_region` if provided)
- `provider.memorySize`: `1024`
- `provider.timeout`: `6`
- `provider.runtime`: **No default** (must be explicit)

## Error Handling

The module provides user-friendly error messages for common issues:

### File Not Found
```
Failed to read configuration file at './nonexistent.yml'.
Please verify the file exists and is readable.
```

### Invalid YAML Syntax
```
Failed to parse YAML configuration from './serverless.yml'.
Please verify the YAML syntax is valid.
```

### Missing Required Fields
```
Configuration validation failed with the following errors:
- Required field 'service' is missing or empty. Specify service name in serverless.yml.
- Required field 'provider.name' must be 'aws', got: 'gcp'.
```

### Multiple Errors Collected
```
Configuration validation failed with the following errors:
- Required field 'service' is missing or empty. Specify service name in serverless.yml.
- Required field 'provider.name' must be 'aws', got: 'none'.
- Function 'hello' missing required 'handler' field.
- Function 'world' has invalid 'memorySize'. Must be between 128 and 10240 MB, got: 99999.
```

## Testing

The module includes comprehensive tests covering:
- YAML parsing and error handling
- Schema validation and error collection
- Default application and inheritance
- Function-level validation
- Functionless configurations
- Region override warnings

Run tests with:
```bash
terraform test
```

## Examples

See the `examples/` directory for:
- `examples/basic/`: Configuration parsing with validation
- `examples/lambda/`: Lambda function deployment with multiple runtimes and environment variables

### Lambda Example

The `examples/lambda/` directory demonstrates:
- Multi-function deployment (Node.js and Python)
- Function-level runtime overrides
- Environment variable configuration
- Custom memory and timeout settings

Run the example:
```bash
cd examples/lambda
terraform init
terraform plan
```

## Roadmap

### Completed
- ✅ **#1: Core Module Structure & YAML Parsing** - Parse and validate Serverless Framework configurations
- ✅ **#2: Lambda Function Translation** - Generate Lambda functions, IAM roles, and code packages

### Completed
- ✅ **#3: IAM Role & Policy Management** - Custom IAM policies from iamRoleStatements

### Completed
- ✅ **#6: TypeScript Configuration Parsing** - Support for serverless.ts files with async exports, complex TypeScript features, and comprehensive error handling

### In Progress
- 🚧 **#4: API Gateway REST API Integration** - HTTP event triggers and API Gateway resources

### Planned
- **#5: S3 Event Source Mapping** - S3 bucket notifications
- **#7: EventBridge Rules & Schedulers** - Schedule and event pattern triggers
- **#8: DynamoDB & SQS Event Sources** - Stream and queue integrations
- And more...

See `agent-os/product/roadmap.md` for the complete roadmap.

## License

[Your License Here]

## Contributing

[Your Contributing Guidelines Here]
