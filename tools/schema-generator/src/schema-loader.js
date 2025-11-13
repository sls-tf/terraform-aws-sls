/**
 * Schema Loader
 *
 * Loads and caches JSON schemas from the file system
 */

const fs = require('fs');
const path = require('path');
const { normalizeSchema, dereferenceSchema } = require('./schema-normalizer');

// Cache for loaded schemas
const schemaCache = new Map();

/**
 * Load a schema file by version
 *
 * @param {string} version - Schema version ('2', '3', '4')
 * @param {Object} options - Loading options
 * @param {boolean} options.normalize - Whether to normalize the schema (default: true)
 * @param {boolean} options.dereference - Whether to dereference $ref pointers (default: false)
 * @param {boolean} options.cache - Whether to use cache (default: true)
 * @returns {Promise<Object>} Loaded schema
 */
async function loadSchema(version, options = {}) {
  const {
    normalize = true,
    dereference = false,
    cache = true
  } = options;

  // Check cache first
  const cacheKey = `${version}-${normalize}-${dereference}`;
  if (cache && schemaCache.has(cacheKey)) {
    return schemaCache.get(cacheKey);
  }

  // Validate version
  if (!['2', '3', '4'].includes(version)) {
    throw new Error(`Invalid schema version: ${version}. Must be '2', '3', or '4'`);
  }

  // Construct schema file path
  const schemaPath = getSchemaPath(version);

  // Load schema from file
  let schema;
  try {
    const content = fs.readFileSync(schemaPath, 'utf8');
    schema = JSON.parse(content);
  } catch (error) {
    if (error.code === 'ENOENT') {
      throw new Error(`Schema file not found: ${schemaPath}`);
    } else if (error instanceof SyntaxError) {
      throw new Error(`Invalid JSON in schema file ${schemaPath}: ${error.message}`);
    } else {
      throw new Error(`Failed to load schema from ${schemaPath}: ${error.message}`);
    }
  }

  // Apply normalization if requested
  if (normalize) {
    try {
      schema = normalizeSchema(schema);
    } catch (error) {
      throw new Error(`Failed to normalize schema v${version}: ${error.message}`);
    }
  }

  // Apply dereferencing if requested
  if (dereference) {
    try {
      schema = await dereferenceSchema(schema);
    } catch (error) {
      throw new Error(`Failed to dereference schema v${version}: ${error.message}`);
    }
  }

  // Cache the result
  if (cache) {
    schemaCache.set(cacheKey, schema);
  }

  return schema;
}

/**
 * Load multiple schemas by version
 *
 * @param {string[]} versions - Array of versions to load
 * @param {Object} options - Loading options
 * @returns {Promise<Object>} Map of version to schema
 */
async function loadSchemas(versions, options = {}) {
  const schemas = {};

  for (const version of versions) {
    schemas[version] = await loadSchema(version, options);
  }

  return schemas;
}

/**
 * Get the file path for a schema version
 *
 * @param {string} version - Schema version
 * @returns {string} Absolute path to schema file
 */
function getSchemaPath(version) {
  // Schemas are in: /path/to/repo/schemas/serverless-framework/v{version}.x.json
  const repoRoot = path.resolve(__dirname, '../../..');
  return path.join(repoRoot, 'schemas', 'serverless-framework', `v${version}.x.json`);
}

/**
 * Check if a schema file exists
 *
 * @param {string} version - Schema version
 * @returns {boolean} True if schema file exists
 */
function schemaExists(version) {
  const schemaPath = getSchemaPath(version);
  return fs.existsSync(schemaPath);
}

/**
 * Clear the schema cache
 */
function clearCache() {
  schemaCache.clear();
}

/**
 * Get cache statistics
 *
 * @returns {Object} Cache statistics
 */
function getCacheStats() {
  return {
    size: schemaCache.size,
    keys: Array.from(schemaCache.keys())
  };
}

module.exports = {
  loadSchema,
  loadSchemas,
  getSchemaPath,
  schemaExists,
  clearCache,
  getCacheStats
};
