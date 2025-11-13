// Invalid TypeScript syntax for testing error handling
import { Serverless } from './types';

const serverless: Serverless = {
  service: 'invalid-syntax-service'
  // Missing comma - this will cause a syntax error
  frameworkVersion: '3',
  provider: {
    name: 'aws',
    // Missing colon - this will cause a syntax error
    runtime 'nodejs18.x'
  }
};

export default serverless;