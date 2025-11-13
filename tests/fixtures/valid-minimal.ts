// Minimal valid TypeScript Serverless configuration
const serverless = {
  service: 'my-typescript-service',
  frameworkVersion: '3',
  provider: {
    name: 'aws',
    runtime: 'nodejs18.x',
    region: 'us-east-1',
    stage: 'dev'
  }
};

export default serverless;