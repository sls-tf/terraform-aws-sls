#!/usr/bin/env node

/**
 * Elemental Event-Driven Service to Serverless Framework Converter
 *
 * This script converts the custom elemental-event-driven-service YAML configuration
 * to a Serverless Framework serverless.yml configuration that can be used with sls.tf
 */

const fs = require('fs');
const path = require('path');
const yaml = require('js-yaml');

function main() {
  const inputFile = process.argv[2];
  const outputFile = process.argv[3] || 'serverless.yml';

  if (!inputFile) {
    console.error('Usage: node elemental-to-serverless-converter.js <input.yaml> [output.yml]');
    process.exit(1);
  }

  try {
    // Read the elemental service configuration
    const elementalConfig = yaml.load(fs.readFileSync(inputFile, 'utf8'));

    // Convert to Serverless Framework format
    const serverlessConfig = convertToServerless(elementalConfig);

    // Write the output
    const yamlOutput = yaml.dump(serverlessConfig, {
      indent: 2,
      lineWidth: 120,
      noRefs: true,
      sortKeys: false
    });

    fs.writeFileSync(outputFile, yamlOutput);
    console.log(`✅ Successfully converted ${inputFile} to ${outputFile}`);

    // Show summary
    console.log('\n📊 Conversion Summary:');
    console.log(`  Service: ${serverlessConfig.service}`);
    console.log(`  Functions: ${Object.keys(serverlessConfig.functions || {}).length}`);
    console.log(`  DynamoDB Tables: ${Object.keys(serverlessConfig.resources?.Resources || {}).filter(k => k.startsWith('DynamoDB')).length}`);
    console.log(`  EventBridge Rules: ${Object.keys(serverlessConfig.resources?.Resources || {}).filter(k => k.includes('EventBridge')).length}`);

  } catch (error) {
    console.error('❌ Conversion failed:', error.message);
    process.exit(1);
  }
}

function convertToServerless(elementalConfig) {
  const serverless = {
    service: elementalConfig.service?.name || 'elemental-service',
    frameworkVersion: '3',
    configValidationMode: 'error',

    provider: {
      name: 'aws',
      runtime: elementalConfig.defaults?.lambda?.runtime || 'nodejs22.x',
      region: 'us-east-1',
      stage: 'dev',
      timeout: elementalConfig.defaults?.lambda?.timeout || 30,
      memorySize: elementalConfig.defaults?.lambda?.memory_size || 256,

      // IAM role statements for the service
      iam: {
        role: {
          statements: [
            {
              Effect: 'Allow',
              Action: [
                'dynamodb:GetItem',
                'dynamodb:PutItem',
                'dynamodb:UpdateItem',
                'dynamodb:DeleteItem',
                'dynamodb:Query',
                'dynamodb:Scan',
                'dynamodb:BatchGetItem',
                'dynamodb:BatchWriteItem'
              ],
              Resource: []
            },
            {
              Effect: 'Allow',
              Action: [
                'events:PutEvents',
                'events:PutRule',
                'events:DeleteRule',
                'events:ListTargetsByRule',
                'events:PutTargets',
                'events:RemoveTargets'
              ],
              Resource: '*'
            },
            {
              Effect: 'Allow',
              Action: [
                'logs:CreateLogGroup',
                'logs:CreateLogStream',
                'logs:PutLogEvents'
              ],
              Resource: 'arn:aws:logs:*:*:*'
            }
          ]
        }
      },

      // Environment variables
      environment: {}
    },

    functions: {},

    resources: {
      Resources: {}
    },

    custom: {
      // Preserve custom configuration
      ...elementalConfig.custom,
      originalElementalConfig: elementalConfig
    }
  };

  // Convert Lambda functions
  if (elementalConfig.lambdas) {
    for (const [name, lambdaConfig] of Object.entries(elementalConfig.lambdas)) {
      serverless.functions[name] = convertLambdaFunction(name, lambdaConfig, elementalConfig);
    }
  }

  // Convert DynamoDB tables
  if (elementalConfig.dynamodb_tables) {
    for (const [name, tableConfig] of Object.entries(elementalConfig.dynamodb_tables)) {
      const dynamoDbResource = convertDynamoDBTable(name, tableConfig, elementalConfig);
      serverless.resources.Resources[`DynamoDB${capitalize(name)}Table`] = dynamoDbResource;

      // Add IAM permission for this table
      const tableArn = `arn:aws:dynamodb:*:*:table/${tableConfig.table_name}`;
      serverless.provider.iam.role.statements[0].Resource.push(tableArn);
    }
  }

  // Convert EventBridge configuration (note: limited support in current sls.tf)
  if (elementalConfig.eventbridge) {
    // Add EventBridge event sources to functions
    if (elementalConfig.eventbridge.rules) {
      for (const [ruleName, ruleConfig] of Object.entries(elementalConfig.eventbridge.rules)) {
        for (const target of ruleConfig.targets || []) {
          if (target.type === 'lambda' && serverless.functions[target.lambda]) {
            // Add EventBridge event to the lambda function
            if (!serverless.functions[target.lambda].events) {
              serverless.functions[target.lambda].events = [];
            }
            serverless.functions[target.lambda].events.push({
              eventBridge: {
                pattern: ruleConfig.event_pattern
              }
            });
          }
        }
      }
    }
  }

  // Convert API Gateway configuration
  if (elementalConfig.api_gateway?.enabled) {
    convertAPIGateway(elementalConfig.api_gateway, serverless, elementalConfig);
  }

  return serverless;
}

function convertLambdaFunction(name, config, elementalConfig) {
  const lambdaFunction = {
    description: config.description || `Lambda function: ${name}`,
    handler: config.handler || 'handler.handler',
    runtime: config.runtime || elementalConfig.defaults?.lambda?.runtime || 'nodejs22.x',
    timeout: config.timeout || elementalConfig.defaults?.lambda?.timeout || 30,
    memorySize: config.memory_size || elementalConfig.defaults?.lambda?.memory_size || 256,
    environment: {
      ...(elementalConfig.defaults?.lambda?.environment || {}),
      ...(config.environment || {})
    },
    events: []
  };

  // Add EventBridge event sources
  if (elementalConfig.eventbridge?.rules) {
    for (const [ruleName, ruleConfig] of Object.entries(elementalConfig.eventbridge.rules)) {
      const hasTarget = ruleConfig.targets?.some(target => target.lambda === name);
      if (hasTarget) {
        lambdaFunction.events.push({
          eventBridge: {
            pattern: ruleConfig.event_pattern
          }
        });
      }
    }
  }

  // Add API Gateway events (would need more complex mapping for actual endpoints)
  if (elementalConfig.api_gateway?.enabled && name.includes('api')) {
    lambdaFunction.events.push({
      http: {
        path: '/{proxy+}',
        method: 'post',
        cors: true
      }
    });
    lambdaFunction.events.push({
      http: {
        path: '/{proxy+}',
        method: 'get',
        cors: true
      }
    });
    lambdaFunction.events.push({
      http: {
        path: '/{proxy+}',
        method: 'put',
        cors: true
      }
    });
    lambdaFunction.events.push({
      http: {
        path: '/{proxy+}',
        method: 'delete',
        cors: true
      }
    });
  }

  // Add stream events from DynamoDB tables
  if (elementalConfig.dynamodb_tables) {
    for (const [tableName, tableConfig] of Object.entries(elementalConfig.dynamodb_tables)) {
      if (tableConfig.stream_view_type && shouldProcessStream(name, tableName, elementalConfig)) {
        // Note: Stream events will be added after the DynamoDB table is created
        // We'll handle this with a separate approach since sls.tf doesn't support
        // direct Fn::GetAtt for stream ARNs in this context
      }
    }
  }

  // Add DLQ configuration
  if (config.dlq?.enabled) {
    const dlqName = config.dlq.name || `${name}-dlq`;
    const dlqArn = {
      'Fn::GetAtt': [`${capitalize(name)}DLQ`, 'Arn']
    };
    lambdaFunction.deadLetterArn = dlqArn;
  }

  return lambdaFunction;
}

function convertDynamoDBTable(name, config, elementalConfig) {
  const resource = {
    Type: 'AWS::DynamoDB::Table',
    Properties: {
      TableName: config.table_name,
      AttributeDefinitions: config.attributes?.map(attr => ({
        AttributeName: attr.name,
        AttributeType: attr.type
      })) || [],
      KeySchema: [
        {
          AttributeName: config.hash_key,
          KeyType: 'HASH'
        }
      ],
      BillingMode: config.billing_mode || 'PAY_PER_REQUEST',
      StreamSpecification: config.stream_view_type ? {
        StreamViewType: config.stream_view_type
      } : undefined,
      PointInTimeRecoverySpecification: config.pitr_enabled ? {
        PointInTimeRecoveryEnabled: true
      } : undefined,
      SSESpecification: {
        SSEEnabled: true
      }
    }
  };

  // Add range key if specified
  if (config.range_key) {
    resource.Properties.KeySchema.push({
      AttributeName: config.range_key,
      KeyType: 'RANGE'
    });
  }

  // Add TTL attribute if specified
  if (config.ttl_attribute) {
    resource.Properties.TimeToLiveSpecification = {
      AttributeName: config.ttl_attribute,
      Enabled: true
    };
  }

  // Add Global Secondary Indexes if specified
  if (config.global_secondary_indexes) {
    resource.Properties.GlobalSecondaryIndexes = config.global_secondary_indexes;
  }

  // Remove undefined values
  Object.keys(resource.Properties).forEach(key => {
    if (resource.Properties[key] === undefined) {
      delete resource.Properties[key];
    }
  });

  return resource;
}

function convertEventBridge(eventbridgeConfig, serverless, elementalConfig) {
  // Note: EventBridge bus and rules are handled as function events in sls.tf
  // This function is intentionally left empty to avoid creating unsupported resources
}

function convertAPIGateway(apiConfig, serverless, elementalConfig) {
  // Note: Full API Gateway conversion would be more complex
  // For now, we rely on Serverless Framework's automatic API Gateway creation
  // when functions have HTTP events

  serverless.provider.apiGateway = {
    minimumCompressionSize: 1024,
    restApiId: {
      'Fn::ImportValue': `${serverless.service}-api-id`
    },
    restApiRootResourceId: {
      'Fn::ImportValue': `${serverless.service}-api-root-id`
    }
  };
}

function shouldProcessStream(lambdaName, tableName, elementalConfig) {
  // Simple heuristic: if lambda name contains table name or vice versa
  return lambdaName.toLowerCase().includes(tableName.toLowerCase()) ||
         tableName.toLowerCase().includes(lambdaName.toLowerCase()) ||
         lambdaName.includes('processor');
}

function capitalize(str) {
  return str.charAt(0).toUpperCase() + str.slice(1);
}

// Execute the main function
if (require.main === module) {
  main();
}

module.exports = { convertToServerless };