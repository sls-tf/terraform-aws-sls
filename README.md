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

### Event Source Integration
- **API Gateway REST API**: HTTP event triggers with CORS support and path-based routing
- **API Gateway HTTP API (v2)**: self-created or attach-to-existing, with REQUEST Lambda authorizers and CORS
- **API Gateway WebSocket API**: routes/integrations/stage from `AWS::ApiGatewayV2::Api` (WEBSOCKET)
- **Step Functions**: `AWS::Serverless::StateMachine` with definition substitutions and policy templates
- **S3 Event Notifications**: Object created/removed triggers with prefix/suffix filtering
- **EventBridge & CloudWatch Rules**: Schedule (cron/rate) and event pattern triggers
- **DynamoDB Streams & SQS**: Event source mappings (function `Events:` or standalone `AWS::Lambda::EventSourceMapping`) with batch processing configuration

### Advanced Features
- **IAM Role & Policy Management**: Custom `iamRoleStatements` translated to IAM policies
- **Custom Resource Provisioning**: CloudFormation-style S3, DynamoDB, SNS, SQS, and CloudFront resources from the `resources:` section
- **CloudFront Lambda@Edge**: `cloudFront` event type support for Lambda@Edge associations with viewer/origin request/response triggers
- **TypeScript Configuration**: Parses `serverless.ts` files including async exports
- **Variable Resolution**: Resolves `${self:}` and `${env:}` variable syntax
- **Custom Domains**: Route 53 and API Gateway custom domain management
- **AWS SAM Support**: Parses `template.yaml` files with `Transform: AWS::Serverless-2016-10-31`
- **LocalStack Support**: Dual-mode testing with LocalStack for local development

## Requirements

- Terraform >= 1.0.0
- AWS Provider >= 6.0
- Null Provider >= 3.0
- Archive Provider >= 2.0
- External Provider >= 2.0 (for SAM and TypeScript config formats)
- Node.js (for SAM and TypeScript config formats — runs the parser at plan time):
  `>= 14` for SAM, `>= 22.7` for TypeScript

**No `npm install` is required for any config format.** YAML (`serverless.yml`)
needs no Node.js. SAM (`config_format = "sam"`) needs `node` on PATH and uses a
vendored, tree-shaken `js-yaml` committed under `scripts/vendor/` (see
`scripts/vendor/js-yaml/VENDOR.md`). TypeScript (`serverless.ts`) runs on Node's
built-in TypeScript support (Node >= 22.7), so it too needs only `node`. Every
path stays self-contained and works offline.

### TypeScript Support

`serverless.ts` is executed at plan time using **Node's native TypeScript
support** (Node >= 22.7) with **zero dependencies** — nothing to install. This
handles standard, self-contained config files.

For a config that needs more than native type-stripping — module-scope
`require()`, extensionless relative imports (`from './types'`), or `tsconfig`
path aliases — set the `SLS_TF_TS_RUNNER` environment variable to a TypeScript
runner that provides full module resolution, such as [`tsx`](https://tsx.is):

```bash
export SLS_TF_TS_RUNNER="npx tsx"   # or "ts-node", "bun", etc.
terraform plan
```

The module then runs your config through that runner instead of native Node. If
the native engine hits a config it can't resolve, it fails at plan time with a
message pointing to this variable. On Node < 22.7 it likewise fails loud with
upgrade / `SLS_TF_TS_RUNNER` guidance rather than attempting a network install.

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

### CloudFront Lambda@Edge

Use the `cloudFront` event type to attach Lambda functions to CloudFront as Lambda@Edge:

```yaml
# serverless.yml
service: my-edge-service
frameworkVersion: '3'

provider:
  name: aws
  runtime: nodejs18.x
  region: us-east-1  # Lambda@Edge requires us-east-1

functions:
  viewerAuth:
    handler: edge/auth.handler
    memorySize: 128  # Viewer functions: max 128 MB
    timeout: 5       # Viewer functions: max 5 seconds
    events:
      - cloudFront:
          eventType: viewer-request
          origin: https://www.example.com
          behavior:
            ViewerProtocolPolicy: redirect-to-https
            AllowedMethods: [GET, HEAD, OPTIONS]

  apiTransform:
    handler: edge/transform.handler
    memorySize: 512
    timeout: 30      # Origin functions: max 30 seconds
    events:
      - cloudFront:
          eventType: origin-request
          origin: https://api.example.com
          pathPattern: /api/*
          behavior:
            ViewerProtocolPolicy: https-only
            ForwardedValues:
              QueryString: true
              Headers: [Authorization]
```

```hcl
module "serverless" {
  source      = "path/to/sls.tf"
  config_path = "${path.module}/serverless.yml"
}

output "edge_distribution_domains" {
  value = module.serverless.lambda_edge_distribution_domain_names
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

## AWS SAM Support

Use `config_format = "sam"` to deploy from an AWS SAM `template.yaml`:

```hcl
module "serverless" {
  source        = "path/to/sls.tf"
  config_path   = "${path.module}/template.yaml"
  config_format = "sam"

  # Optional: override SAM template Parameters
  sam_template_parameters = {
    Stage = "prod"
  }
}
```

### Supported SAM Resource Types

| SAM Type | Terraform Output |
|---|---|
| `AWS::Serverless::Function` | `aws_lambda_function` + IAM role |
| `AWS::Serverless::SimpleTable` | `aws_dynamodb_table` (PAY_PER_REQUEST) |
| `AWS::S3::Bucket` | `aws_s3_bucket` |
| `AWS::DynamoDB::Table` | `aws_dynamodb_table` |
| `AWS::SNS::Topic` | `aws_sns_topic` |
| `AWS::SQS::Queue` | `aws_sqs_queue` |
| `AWS::CloudFront::Distribution` | `aws_cloudfront_distribution` |
| `AWS::Serverless::HttpApi` (self-created) | `aws_apigatewayv2_api` (HTTP) + routes/integrations/stage/authorizer |
| `AWS::ApiGatewayV2::Api` (WEBSOCKET) | `aws_apigatewayv2_api` (WEBSOCKET) + routes/integrations/stage |
| `AWS::Serverless::StateMachine` | `aws_sfn_state_machine` + execution role |

### Supported SAM Event Types

| SAM Event | SLS Equivalent | Notes |
|---|---|---|
| `Api` / `HttpApi` | `http` | Path and method routing; self-created or attach-to-existing HTTP API |
| `S3` | `s3` | Object created/removed triggers |
| `DynamoDB` | `stream` | Stream event source mappings |
| `SQS` | `sqs` | Queue event source mappings |
| `Schedule` | `schedule` | cron/rate expressions |
| `EventBridgeRule` | `eventBridge` | Event pattern rules |

### HTTP APIs (v2): self-created vs attach-to-existing

An `HttpApi` function event is handled in one of three ways, chosen automatically
from its `ApiId`:

- **No `ApiId`** — a v1 REST API (`aws_api_gateway_rest_api`) is self-created (the
  original behaviour).
- **`ApiId: !Ref <HttpApiLogicalId>`** referencing an inline
  `AWS::Serverless::HttpApi` resource — the module **self-creates** the HTTP API
  (`aws_apigatewayv2_api`, protocol `HTTP`) with its integrations, routes, a
  `$default` auto-deploy stage, CORS from the resource's `CorsConfiguration`, and
  a REQUEST Lambda authorizer from `Auth.Authorizers`.
- **`ApiId: <real-api-id>`** (a literal id owned by another stack) — the routes
  **attach to that existing** HTTP API; the API itself is not managed here.

The authorizer name on an event is read from either `Properties.Auth.Authorizer`
(standard SAM) or `Properties.Authorizer`.

### WebSocket APIs

An `AWS::ApiGatewayV2::Api` with `ProtocolType: WEBSOCKET`, together with its
`AWS::ApiGatewayV2::Route`, `::Integration`, and `::Stage` resources, is created
as a Terraform WebSocket API: `aws_apigatewayv2_api` (WEBSOCKET) +
`_integration` (AWS_PROXY) + `_route` + `_stage` (auto-deploy) + Lambda invoke
permissions. Routes are wired to their integrations and integrations to their
target functions via the `!Ref`/`!GetAtt` references in `Target`/`IntegrationUri`.
`AWS::ApiGatewayV2::Deployment` is subsumed by stage auto-deploy, and explicit
`AWS::Lambda::Permission` resources are subsumed by the module's own permissions.

### Step Functions (State Machines)

`AWS::Serverless::StateMachine` (and `AWS::StepFunctions::StateMachine`) become
`aws_sfn_state_machine` plus an execution role. The `DefinitionUri` JSON (relative
to `lambda_code_path`) is rendered with `DefinitionSubstitutions` (the `${Key}`
placeholders), and `Policies` entries — `LambdaInvokePolicy` templates and inline
`Statement` documents — are translated into the role's policy.

### SAM Globals Section

`Globals.Function` settings (Runtime, MemorySize, Timeout, Environment) are applied to
all functions and can be overridden per-function. `Globals.Api` is recognized but
route configuration is driven by per-function events.

### CloudFormation Intrinsic Functions

A vendored Node preprocessor (`scripts/sam-preprocessor.js`) evaluates CFN
intrinsics before the template reaches Terraform. Both the **short tag** form
(`!Sub`, `!Ref`, `!GetAtt`, `!Join`, `!If`, …) and the **full object** form
(`Fn::Sub`, `Ref`, `Fn::GetAtt`, `Fn::Join`, …) are supported and may be mixed in
the same template. `!Ref`/`!GetAtt` to template resources resolve to the
resource's deterministic name/ARN (region + account + resolved name); references
that can't be resolved are left as a marker string the module recognises (e.g.
when wiring routes/integrations by logical ID).

For `DynamoDB` and `SQS` events that use `!GetAtt`/`!Ref` to reference stream ARNs or
queue ARNs, these values are passed through to the event source mapping resource
and resolved at apply time by AWS. ARN format validation is skipped for SAM format.

### Controlling Which Resources Get Created

The `resource_types` variable lets the infrastructure team decide what a service
template is permitted to materialise in real AWS, without touching the template itself.
This is useful when developers use a full SAM template for `sam local` but only a
subset of resources should be Terraform-managed:

```hcl
# Lambda only — infra team owns everything else
module "event_service" {
  source        = "path/to/sls.tf"
  config_path   = "${path.module}/template.yaml"
  config_format = "sam"

  resource_types = ["AWS::Serverless::Function"]
}

# Lambda plus a tightly-coupled table the team owns end-to-end
module "users_service" {
  source        = "path/to/sls.tf"
  config_path   = "${path.module}/template.yaml"
  config_format = "sam"

  resource_types = [
    "AWS::Serverless::Function",
    "AWS::DynamoDB::Table",
  ]
}
```

`resource_types` filters the `resources:` / `Resources:` section only. Lambda
functions, IAM roles, API Gateway, S3 notifications, EventBridge rules, and
DynamoDB/SQS event source mappings are always created — those are event wiring,
not standalone infrastructure. Omit `resource_types` (or set it to `null`) to
restore the default behaviour of creating all supported resource types.

Resource types not in `supported_resource_types` are silently skipped rather than
raising a validation error when they are explicitly excluded by `resource_types`.

### Unsupported SAM Types

`AWS::Serverless::LayerVersion` and `AWS::Serverless::Application` are not yet
translated. Resources of these types are excluded from the Terraform plan silently.

## Input Variables

| Name | Type | Default | Required | Description |
|------|------|---------|----------|-------------|
| `config_path` | string | - | yes | Path to the configuration file (serverless.yml, serverless.ts, or SAM template.yaml) |
| `config_format` | string | `"yaml"` | no | Format of the configuration file. Options: `"yaml"`, `"typescript"`, or `"sam"`. |
| `lambda_code_path` | string | `"."` | no | Path to Lambda function code directory to package. Defaults to current directory. |
| `aws_region` | string | `null` | no | Optional AWS region override. If set and differs from the config region, a warning will be displayed. |
| `sam_template_parameters` | map(string) | `{}` | no | Parameter values for SAM templates. Keys must match names in the template `Parameters` section. |
| `resource_types` | list(string) | `null` | no | Allowlist of CloudFormation resource types to materialise from the `resources:` section. `null` creates all types. Lambda functions, IAM roles, and event wiring are always created regardless. |

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

### CloudFront Lambda@Edge Outputs
| Name | Type | Description |
|------|------|-------------|
| `lambda_edge_distribution_ids` | map(string) | CloudFront distribution IDs keyed by distribution group name |
| `lambda_edge_distribution_arns` | map(string) | CloudFront distribution ARNs keyed by distribution group name |
| `lambda_edge_distribution_domain_names` | map(string) | CloudFront domain names keyed by distribution group name |
| `lambda_edge_distribution_count` | number | Total count of Lambda@Edge CloudFront distributions created |
| `custom_cloudfront_distribution_ids` | map(string) | Distribution IDs from `resources:` section, keyed by logical ID |
| `custom_cloudfront_distribution_arns` | map(string) | Distribution ARNs from `resources:` section, keyed by logical ID |
| `custom_cloudfront_distribution_domain_names` | map(string) | Domain names from `resources:` section, keyed by logical ID |

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

### CloudFront Lambda@Edge Validation
- `cloudFront.eventType`: Must be `viewer-request`, `viewer-response`, `origin-request`, or `origin-response`
- `cloudFront.origin`: Required (string URL or origin object)
- `cloudFront.includeBody`: Only valid for `viewer-request` and `origin-request` events
- Viewer-side functions (`viewer-request`/`viewer-response`): `timeout` <= 5 seconds, `memorySize` <= 128 MB
- Origin-side functions (`origin-request`/`origin-response`): `timeout` <= 30 seconds

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
- ✅ **#3: IAM Role & Policy Management** - Custom IAM policies from iamRoleStatements
- ✅ **#4: API Gateway REST API Integration** - HTTP event triggers, CORS, and path-based routing
- ✅ **#5: S3 Event Source Mapping** - S3 bucket notifications with prefix/suffix filtering
- ✅ **#6: TypeScript Configuration Parsing** - Support for serverless.ts files with async exports
- ✅ **#7: EventBridge Rules & Schedulers** - Schedule (cron/rate) and event pattern triggers
- ✅ **#8: DynamoDB & SQS Event Sources** - Stream and queue event source mappings
- ✅ **#9: Custom Resource Provisioning** - CloudFormation-style S3, DynamoDB, SNS, SQS, CloudFront from `resources:` section
- ✅ **#10: LocalStack Integration** - Dual-mode testing infrastructure with LocalStack
- ✅ **#11: Variable Resolution Engine** - `${self:}` and `${env:}` variable syntax support
- ✅ **#12: CloudFront Distribution Support** - `cloudFront` event type for Lambda@Edge (viewer/origin request/response) plus CloudFormation-style distribution resources
- ✅ **#13: Route 53 & Custom Domain Management** - Custom domain provisioning with API Gateway
- ✅ **#14: Schema Synchronization Tooling** - Automated tooling to sync validation with Serverless Framework schema

See `agent-os/product/roadmap.md` for the complete roadmap.

## License

[Your License Here]

## Contributing

[Your Contributing Guidelines Here]
