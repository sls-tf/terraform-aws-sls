#!/usr/bin/env node

/**
 * TypeScript Configuration Parser for sls.tf
 *
 * This script parses Serverless Framework TypeScript configuration files
 * and converts them to JSON for Terraform consumption.
 *
 * Usage: node typescript-parser.js <config-path> [working-directory]
 */

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

function main() {
  let input;
  try {
    // Parse input from Terraform external data source
    input = JSON.parse(fs.readFileSync(0, 'utf8'));
    const { config_path, working_directory = '.' } = input;

    if (!config_path) {
      throw new Error('config_path is required');
    }

    // Resolve the config file path relative to working directory
    const resolvedWorkingDir = path.resolve(working_directory);
    const resolvedConfigPath = path.resolve(resolvedWorkingDir, config_path);

    // Validate file exists
    if (!fs.existsSync(resolvedConfigPath)) {
      throw new Error(`Configuration file not found: ${resolvedConfigPath}`);
    }

    // Check if TypeScript dependencies are available
    try {
      require.resolve('ts-node');
      require.resolve('typescript');
    } catch (error) {
      throw new Error(`TypeScript dependencies not found. Please install: npm install ts-node typescript. Error: ${error.message}`);
    }

    // Create a temporary TypeScript execution script
    const tempScript = createTempScript(resolvedConfigPath, resolvedWorkingDir);

    try {
      // Execute TypeScript parsing with ts-node
      const result = execSync(`npx ts-node "${tempScript}"`, {
        cwd: resolvedWorkingDir,
        encoding: 'utf8',
        timeout: 30000, // 30 second timeout
        stdio: ['pipe', 'pipe', 'pipe']
      });

      // Parse the result and validate it's valid JSON
      let parsedConfig;
      try {
        parsedConfig = JSON.parse(result.trim());
      } catch (parseError) {
        throw new Error(`Failed to parse TypeScript output as JSON: ${parseError.message}. Output: ${result}`);
      }

      // Validate the parsed configuration
      validateServerlessConfig(parsedConfig);

      // Return success response
      console.log(JSON.stringify({
        status: 'success',
        config: JSON.stringify(parsedConfig),
        config_path: resolvedConfigPath
      }));

    } finally {
      // Clean up temporary script
      if (fs.existsSync(tempScript)) {
        fs.unlinkSync(tempScript);
      }
    }

  } catch (error) {
    // Return error response
    console.log(JSON.stringify({
      status: 'error',
      error: error.message,
      config_path: input ? input.config_path : 'unknown'
    }));
    process.exit(1);
  }
}

/**
 * Create a temporary TypeScript script to load and parse the configuration
 */
function createTempScript(configPath, workingDir) {
  const tempScript = path.join(workingDir, `.temp-config-parser-${Date.now()}.ts`);

  const scriptContent = `
import * as path from 'path';
import * as fs from 'fs';

// Set working directory
process.chdir('${workingDir.replace(/\\/g, '\\\\')}');

async function loadConfig() {
  try {
    // Resolve config path relative to working directory
    const resolvedPath = path.resolve('${configPath.replace(/\\/g, '\\\\')}');

    // Import the TypeScript module
    const configModule = await import(resolvedPath);

    // Handle different export formats
    let config = configModule.default || configModule;

    // Handle async function exports
    if (typeof config === 'function') {
      config = await config();
    }

    // Handle Promise exports
    if (config && typeof config.then === 'function') {
      config = await config;
    }

    // Validate configuration object
    if (!config || typeof config !== 'object') {
      throw new Error('Configuration must export an object');
    }

    // Return the configuration as JSON
    console.log(JSON.stringify(config, null, 2));

  } catch (error) {
    console.error('Error loading TypeScript configuration:', (error as Error).message);
    console.error('Stack:', (error as Error).stack);
    process.exit(1);
  }
}

// Execute the configuration loading
loadConfig().catch(error => {
  console.error('Unhandled error:', (error as Error).message);
  process.exit(1);
});
`;

  fs.writeFileSync(tempScript, scriptContent);
  return tempScript;
}

/**
 * Validate basic Serverless Framework configuration structure
 */
function validateServerlessConfig(config) {
  if (!config.service) {
    throw new Error('Missing required field: service');
  }

  if (!config.provider || !config.provider.name || config.provider.name !== 'aws') {
    throw new Error('Missing or invalid provider configuration. Provider name must be "aws".');
  }

  // Validate functions if they exist
  if (config.functions) {
    for (const [funcName, funcConfig] of Object.entries(config.functions)) {
      if (!funcConfig.handler) {
        throw new Error(`Function "${funcName}" missing required "handler" field`);
      }
    }
  }
}

// Execute the main function
if (require.main === module) {
  main();
}

module.exports = { main, validateServerlessConfig };