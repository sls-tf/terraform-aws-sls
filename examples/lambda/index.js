// Simple Node.js Lambda handler
exports.handler = async (event) => {
  const greeting = process.env.GREETING || 'Hello';
  const environment = process.env.ENVIRONMENT || 'unknown';

  return {
    statusCode: 200,
    body: JSON.stringify({
      message: `${greeting} from ${environment}!`,
      event: event
    })
  };
};
