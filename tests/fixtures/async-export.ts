// Async function export example
async function loadConfig() {
  // Simulate async configuration loading
  await new Promise(resolve => setTimeout(resolve, 100));

  const stage = process.env.NODE_ENV || 'dev';

  return {
    service: 'async-service',
    frameworkVersion: '3',
    provider: {
      name: 'aws',
      runtime: 'nodejs18.x',
      region: 'us-east-1',
      stage
    },
    functions: {
      handler: {
        handler: 'src/index.handler',
        environment: {
          STAGE: stage
        }
      }
    }
  };
}

export default loadConfig;