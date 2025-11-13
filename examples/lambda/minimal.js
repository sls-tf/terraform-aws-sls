// Minimal Lambda handler without environment variables
exports.handler = async (event) => {
  return {
    statusCode: 200,
    body: JSON.stringify({ message: 'Minimal function' })
  };
};
