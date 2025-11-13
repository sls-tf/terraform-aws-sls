/**
 * Configuration Loader
 *
 * Loads and validates configuration files for the schema generator
 */

const fs = require('fs');
const path = require('path');
const yaml = require('js-yaml');

/**
 * Default configuration
 */
const DEFAULT_CONFIG = {
  included_paths: [
    '/properties/service',
    '/properties/provider',
    '/properties/functions'
  ],
  excluded_paths: [
    '/properties/plugins',
    '/properties/package'
  ]
};

/**
 * Load configuration from file
 *
 * @param {string} configPath - Path to configuration file
 * @param {Object} options - Loading options
 * @param {boolean} options.useDefaults - Use defaults if file not found (default: true)
 * @returns {Object} Configuration object
 */
function loadConfig(configPath, options = {}) {
  const { useDefaults = true } = options;

  // Check if file exists
  if (!fs.existsSync(configPath)) {
    if (useDefaults) {
      console.warn(`Config file not found: ${configPath}. Using defaults.`);
      return DEFAULT_CONFIG;
    } else {
      throw new Error(`Configuration file not found: ${configPath}`);
    }
  }

  // Read file content
  let content;
  try {
    content = fs.readFileSync(configPath, 'utf8');
  } catch (error) {
    throw new Error(`Failed to read config file ${configPath}: ${error.message}`);
  }

  // Parse YAML
  let config;
  try {
    config = yaml.load(content);
  } catch (error) {
    throw new Error(`Failed to parse YAML in ${configPath}: ${error.message}`);
  }

  // Validate configuration
  validateConfig(config);

  // Merge with defaults for any missing fields
  const mergedConfig = {
    included_paths: config.included_paths || DEFAULT_CONFIG.included_paths,
    excluded_paths: config.excluded_paths || DEFAULT_CONFIG.excluded_paths
  };

  return mergedConfig;
}

/**
 * Validate configuration structure
 *
 * @param {Object} config - Configuration to validate
 * @throws {Error} If configuration is invalid
 */
function validateConfig(config) {
  if (!config || typeof config !== 'object') {
    throw new Error('Configuration must be an object');
  }

  // Validate included_paths
  if (config.included_paths !== undefined) {
    if (!Array.isArray(config.included_paths)) {
      throw new Error('included_paths must be an array');
    }
    config.included_paths.forEach((path, index) => {
      if (typeof path !== 'string') {
        throw new Error(`included_paths[${index}] must be a string`);
      }
      if (!path.startsWith('/')) {
        throw new Error(`included_paths[${index}] must start with '/' (JSON pointer format)`);
      }
    });
  }

  // Validate excluded_paths
  if (config.excluded_paths !== undefined) {
    if (!Array.isArray(config.excluded_paths)) {
      throw new Error('excluded_paths must be an array');
    }
    config.excluded_paths.forEach((path, index) => {
      if (typeof path !== 'string') {
        throw new Error(`excluded_paths[${index}] must be a string`);
      }
      if (!path.startsWith('/')) {
        throw new Error(`excluded_paths[${index}] must start with '/' (JSON pointer format)`);
      }
    });
  }
}

/**
 * Create default configuration file
 *
 * @param {string} outputPath - Path where to create the config file
 */
function createDefaultConfig(outputPath) {
  const configContent = `# Schema Generator Configuration
#
# This file controls which parts of the Serverless Framework schema
# are included in the generated Terraform validation code.

# Paths to include from the schema (JSON pointer format)
# Only constraints from these paths will be generated
included_paths:
  - /properties/service          # Service identifier
  - /properties/provider         # Cloud provider configuration
  - /properties/functions        # Lambda function definitions
  # Add more paths as roadmap features are implemented:
  # - /properties/resources      # CloudFormation resources
  # - /properties/custom         # Custom configuration

# Paths to exclude from the schema (JSON pointer format)
# Constraints from these paths will NOT be generated
excluded_paths:
  - /properties/plugins          # Plugin configuration (too variable)
  - /properties/package          # Packaging options (not yet implemented)
  # Add more exclusions as needed

# Notes:
# - Paths use JSON Pointer format: /properties/field/subfield
# - Wildcards are supported: /properties/functions/*
# - Update this file as you implement more roadmap features
# - Run 'npm run generate:validation:all' after updating
`;

  try {
    fs.writeFileSync(outputPath, configContent, 'utf8');
    console.log(`Created default configuration file: ${outputPath}`);
  } catch (error) {
    throw new Error(`Failed to create config file ${outputPath}: ${error.message}`);
  }
}

/**
 * Get the default configuration
 *
 * @returns {Object} Default configuration
 */
function getDefaultConfig() {
  return JSON.parse(JSON.stringify(DEFAULT_CONFIG));
}

module.exports = {
  loadConfig,
  validateConfig,
  createDefaultConfig,
  getDefaultConfig,
  DEFAULT_CONFIG
};
