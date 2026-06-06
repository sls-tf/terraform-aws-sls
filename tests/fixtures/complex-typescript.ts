import type { Serverless } from './types.ts';

// Stand-in for a value that would otherwise come from package.json. Node's
// native TypeScript support runs as ESM and does not provide CommonJS require();
// a config that needs require()/JSON imports must use the SLS_TF_TS_RUNNER hook.
const packageVersion = '1.0.0';

// Complex TypeScript with imports and advanced features
interface DatabaseConfig {
  host: string;
  port: number;
  name: string;
}

interface Environment {
  name: string;
  database: DatabaseConfig;
}

// Complex configuration logic
function createEnvironment(stage: string): Environment {
  const configs: Record<string, Environment> = {
    dev: {
      name: 'development',
      database: {
        host: 'localhost',
        port: 5432,
        name: 'myapp_dev'
      }
    },
    prod: {
      name: 'production',
      database: {
        host: 'prod-db.example.com',
        port: 5432,
        name: 'myapp_prod'
      }
    }
  };

  return configs[stage] || configs.dev;
}

// Dynamic configuration with computed values
const stage = process.env.STAGE || 'dev';
const env = createEnvironment(stage);

const serverless: Serverless = {
  service: 'complex-typescript-service',
  frameworkVersion: '3',
  provider: {
    name: 'aws',
    runtime: 'nodejs18.x',
    region: 'us-east-1',
    stage,
    memorySize: stage === 'prod' ? 2048 : 512,
    timeout: stage === 'prod' ? 30 : 10,
    environment: {
      NODE_ENV: env.name,
      DB_HOST: env.database.host,
      DB_PORT: env.database.port.toString(),
      DB_NAME: env.database.name,
      SERVICE_VERSION: packageVersion
    }
  },
  functions: {
    api: {
      handler: 'dist/api.handler',
      description: `API Gateway handler for ${env.name} environment`,
      memorySize: stage === 'prod' ? 1024 : 256,
      events: [
        {
          http: {
            path: '/{proxy+}',
            method: 'any',
            cors: {
              origins: stage === 'prod' ? ['https://app.example.com'] : ['*']
            }
          }
        }
      ]
    },
    worker: {
      handler: 'dist/worker.process',
      runtime: 'python3.9',
      memorySize: 1024,
      timeout: 300,
      events: [
        {
          schedule: {
            rate: stage === 'prod' ? 'rate(1 minute)' : 'rate(10 minutes)'
          }
        }
      ]
    }
  },
  custom: {
    ...env,
    serviceVersion: packageVersion,
    deployTime: new Date().toISOString()
  },
  resources: {
    Resources: {
      DatabaseTable: {
        Type: 'AWS::DynamoDB::Table',
        Properties: {
          TableName: `${stage}-items`,
          AttributeDefinitions: [
            { AttributeName: 'id', AttributeType: 'S' },
            { AttributeName: 'createdAt', AttributeType: 'N' }
          ],
          KeySchema: [
            { AttributeName: 'id', KeyType: 'HASH' },
            { AttributeName: 'createdAt', KeyType: 'RANGE' }
          ],
          BillingMode: stage === 'prod' ? 'PROVISIONED' : 'PAY_PER_REQUEST',
          ProvisionedThroughput: stage === 'prod' ? {
            ReadCapacityUnits: 10,
            WriteCapacityUnits: 5
          } : undefined
        }
      }
    }
  }
};

export default serverless;