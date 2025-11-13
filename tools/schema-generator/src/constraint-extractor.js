/**
 * Constraint Extractor
 *
 * Extracts validation constraints from JSON schemas
 */

const { walkSchema } = require('./schema-normalizer');

/**
 * Extract all constraints from a schema
 *
 * @param {Object} schema - JSON schema to extract constraints from
 * @param {Object} options - Extraction options
 * @param {string} options.basePath - Base path for constraint paths (default: '#')
 * @returns {Object} Extracted constraints organized by type
 */
function extractConstraints(schema, options = {}) {
  const { basePath = '#' } = options;

  const constraints = {
    required: [],
    types: [],
    enums: [],
    patterns: [],
    ranges: [],
    conditionals: []
  };

  // Walk schema and extract constraints
  extractFromNode(schema, basePath, constraints);

  return constraints;
}

/**
 * Extract constraints from a single schema node
 *
 * @param {Object} node - Schema node
 * @param {string} path - JSON pointer path to this node
 * @param {Object} constraints - Constraints object to populate
 */
function extractFromNode(node, path, constraints) {
  if (!node || typeof node !== 'object') {
    return;
  }

  // Extract required fields
  if (node.required && Array.isArray(node.required)) {
    node.required.forEach(fieldName => {
      constraints.required.push({
        path: path,
        field: fieldName,
        schemaPath: `${path}/required`
      });
    });
  }

  // Extract type constraints
  if (node.type) {
    const types = Array.isArray(node.type) ? node.type : [node.type];
    types.forEach(type => {
      constraints.types.push({
        path: path,
        type: type,
        schemaPath: `${path}/type`
      });
    });
  }

  // Extract enum constraints
  if (node.enum && Array.isArray(node.enum)) {
    constraints.enums.push({
      path: path,
      values: node.enum,
      schemaPath: `${path}/enum`,
      description: node.description
    });
  }

  // Extract pattern constraints
  if (node.pattern) {
    constraints.patterns.push({
      path: path,
      pattern: node.pattern,
      schemaPath: `${path}/pattern`,
      description: node.description
    });
  }

  // Extract range constraints (minimum, maximum)
  if (node.minimum !== undefined || node.maximum !== undefined ||
      node.exclusiveMinimum !== undefined || node.exclusiveMaximum !== undefined) {
    constraints.ranges.push({
      path: path,
      minimum: node.minimum,
      maximum: node.maximum,
      exclusiveMinimum: node.exclusiveMinimum,
      exclusiveMaximum: node.exclusiveMaximum,
      schemaPath: `${path}`,
      description: node.description
    });
  }

  // Extract conditional constraints (if/then/else, dependencies)
  if (node.if || node.dependencies) {
    constraints.conditionals.push({
      path: path,
      if: node.if,
      then: node.then,
      else: node.else,
      dependencies: node.dependencies,
      schemaPath: `${path}`
    });
  }

  // Recurse into properties
  if (node.properties) {
    Object.entries(node.properties).forEach(([key, prop]) => {
      extractFromNode(prop, `${path}/properties/${key}`, constraints);
    });
  }

  // Recurse into patternProperties
  if (node.patternProperties) {
    Object.entries(node.patternProperties).forEach(([pattern, prop]) => {
      // Use pattern as key but mark it as pattern-based
      extractFromNode(prop, `${path}/patternProperties/${pattern}`, constraints);
    });
  }

  // Recurse into items (array schemas)
  if (node.items) {
    if (Array.isArray(node.items)) {
      node.items.forEach((item, index) => {
        extractFromNode(item, `${path}/items/${index}`, constraints);
      });
    } else {
      extractFromNode(node.items, `${path}/items`, constraints);
    }
  }

  // Recurse into allOf, anyOf, oneOf
  ['allOf', 'anyOf', 'oneOf'].forEach(key => {
    if (Array.isArray(node[key])) {
      node[key].forEach((subschema, index) => {
        extractFromNode(subschema, `${path}/${key}/${index}`, constraints);
      });
    }
  });
}

/**
 * Filter constraints by schema path patterns
 *
 * @param {Object} constraints - Constraints to filter
 * @param {string[]} includePaths - Paths to include (JSON pointer patterns)
 * @param {string[]} excludePaths - Paths to exclude (JSON pointer patterns)
 * @returns {Object} Filtered constraints
 */
function filterConstraints(constraints, includePaths = [], excludePaths = []) {
  const filtered = {
    required: [],
    types: [],
    enums: [],
    patterns: [],
    ranges: [],
    conditionals: []
  };

  // Filter each constraint type
  Object.keys(constraints).forEach(type => {
    filtered[type] = constraints[type].filter(constraint => {
      const path = constraint.path || constraint.schemaPath;

      // Check if path matches any exclude pattern
      const isExcluded = excludePaths.some(pattern => matchesPattern(path, pattern));
      if (isExcluded) {
        return false;
      }

      // If include paths specified, check if path matches any include pattern
      if (includePaths.length > 0) {
        return includePaths.some(pattern => matchesPattern(path, pattern));
      }

      // No include paths specified, include by default (unless excluded)
      return true;
    });
  });

  return filtered;
}

/**
 * Check if a path matches a pattern (supports wildcards)
 *
 * @param {string} path - Path to check
 * @param {string} pattern - Pattern to match against (supports * wildcard)
 * @returns {boolean} True if path matches pattern
 */
function matchesPattern(path, pattern) {
  // Normalize paths: remove # prefix if present
  const normalizedPath = path.startsWith('#') ? path.substring(1) : path;
  const normalizedPattern = pattern.startsWith('#') ? pattern.substring(1) : pattern;

  // Exact match
  if (normalizedPath === normalizedPattern) {
    return true;
  }

  // Prefix match with wildcard
  if (normalizedPattern.endsWith('/*')) {
    const prefix = normalizedPattern.slice(0, -2);
    return normalizedPath.startsWith(prefix);
  }

  // Check if path starts with pattern (for broader matching)
  if (normalizedPath.startsWith(normalizedPattern)) {
    return true;
  }

  // Glob-style pattern matching
  const regexPattern = normalizedPattern
    .replace(/[.*+?^${}()|[\]\\]/g, '\\$&') // Escape special chars
    .replace(/\\\*/g, '.*'); // Convert * to .*

  const regex = new RegExp(`^${regexPattern}$`);
  return regex.test(normalizedPath);
}

/**
 * Get constraint statistics
 *
 * @param {Object} constraints - Constraints object
 * @returns {Object} Statistics about constraints
 */
function getConstraintStats(constraints) {
  return {
    required: constraints.required.length,
    types: constraints.types.length,
    enums: constraints.enums.length,
    patterns: constraints.patterns.length,
    ranges: constraints.ranges.length,
    conditionals: constraints.conditionals.length,
    total: Object.values(constraints).reduce((sum, arr) => sum + arr.length, 0)
  };
}

module.exports = {
  extractConstraints,
  filterConstraints,
  matchesPattern,
  getConstraintStats
};
