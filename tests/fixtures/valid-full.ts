import { Serverless } from './types';

// Full-featured TypeScript Serverless configuration
interface CustomConfig {
  bucketName: string;
  environment: string;
}

const serverless: Serverless = {
  service: {
    name: 'my-full-service',
    // Custom serverless properties
  },
  frameworkVersion: '3',
  provider: {
    name: 'aws',
    runtime: 'nodejs18.x',
    region: 'us-east-1',
    stage: 'production',
    memorySize: 1024,
    timeout: 10,
    environment: {
      NODE_ENV: 'production',
      API_VERSION: 'v1'
    },
    iamRoleStatements: [
      {
        Effect: 'Allow',
        Action: ['dynamodb:GetItem', 'dynamodb:PutItem'],
        Resource: ['arn:aws:dynamodb:*:*:table/my-table']
      }
    ]
  },
  functions: {
    api: {
      handler: 'src/handlers/api.handler',
      description: 'API handler function',
      memorySize: 512,
      timeout: 30,
      environment: {
        TABLE_NAME: 'my-table'
      },
      events: [
        {
          http: {
            path: '/api',
            method: 'get',
            cors: true
          }
        }
      ]
    },
    worker: {
      handler: 'src/handlers/worker.process',
      description: 'Background worker function',
      runtime: 'python3.9',
      memorySize: 2048,
      timeout: 900,
      events: [
        {
          schedule: {
            rate: 'rate(5 minutes)'
          }
        }
      ]
    }
  },
  custom: {
    bucketName: 'my-service-bucket-${self:provider.stage}',
    environment: 'production'
  },
  resources: {
    Resources: {
      MyTable: {
        Type: 'AWS::DynamoDB::Table',
        Properties: {
          TableName: 'my-table',
          AttributeDefinitions: [
            {
              AttributeName: 'id',
              AttributeType: 'S'
            }
          ],
          KeySchema: [
            {
              AttributeName: 'id',
              KeyType: 'HASH'
            }
          ],
          BillingMode: 'PAY_PER_REQUEST'
        }
      }
    }
  }
};

export default serverless;