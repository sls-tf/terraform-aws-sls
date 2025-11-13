/**
 * Schema Normalizer
 *
 * Normalizes JSON schemas from Draft-04 and Draft-06 to Draft-07 format
 */

const Dereferencer = require('@json-schema-tools/dereferencer').default;

/**
 * Normalize a JSON schema to Draft-07 format
 *
 * @param {Object} schema - The JSON schema to normalize
 * @returns {Object} Normalized schema in Draft-07 format
 */
function normalizeSchema(schema) {
  if (!schema || typeof schema !== 'object') {
    throw new Error('Invalid schema: must be an object');
  }

  // Clone schema to avoid mutations
  const normalized = JSON.parse(JSON.stringify(schema));

  // Detect current draft version
  const currentDraft = detectDraft(normalized.$schema);

  // Set $schema to Draft-07 if missing or outdated
  if (!normalized.$schema || currentDraft < 7) {
    normalized.$schema = 'http://json-schema.org/draft-07/schema#';
  }

  // Apply Draft-04 to Draft-07 conversions
  if (currentDraft === 4) {
    convertDraft4ToDraft7(normalized);
  }

  // Apply Draft-06 to Draft-07 conversions
  if (currentDraft === 6) {
    convertDraft6ToDraft7(normalized);
  }

  return normalized;
}

/**
 * Detect JSON Schema draft version from $schema URL
 *
 * @param {string} schemaUrl - The $schema URL
 * @returns {number} Draft version (4, 6, or 7)
 */
function detectDraft(schemaUrl) {
  if (!schemaUrl) {
    return 7; // Default to Draft-07
  }

  if (schemaUrl.includes('draft-04') || schemaUrl.includes('draft-4')) {
    return 4;
  }
  if (schemaUrl.includes('draft-06') || schemaUrl.includes('draft-6')) {
    return 6;
  }
  if (schemaUrl.includes('draft-07') || schemaUrl.includes('draft-7')) {
    return 7;
  }

  // Default to Draft-07 for unknown versions
  return 7;
}

/**
 * Convert Draft-04 schema features to Draft-07
 *
 * @param {Object} schema - Schema to convert (mutated in place)
 */
function convertDraft4ToDraft7(schema) {
  // Walk through schema tree
  walkSchema(schema, (node) => {
    // Draft-04 used "id", Draft-07 uses "$id"
    if (node.id && !node.$id) {
      node.$id = node.id;
      delete node.id;
    }

    // Convert "additionalItems" from boolean to schema object
    if (typeof node.additionalItems === 'boolean' && node.additionalItems === false) {
      // In Draft-07, false means no additional items allowed
      // Keep as-is, it's compatible
    }

    // "exclusiveMinimum" and "exclusiveMaximum" changed from boolean to number
    if (typeof node.exclusiveMinimum === 'boolean') {
      if (node.exclusiveMinimum && node.minimum !== undefined) {
        node.exclusiveMinimum = node.minimum;
        delete node.minimum;
      } else {
        delete node.exclusiveMinimum;
      }
    }

    if (typeof node.exclusiveMaximum === 'boolean') {
      if (node.exclusiveMaximum && node.maximum !== undefined) {
        node.exclusiveMaximum = node.maximum;
        delete node.maximum;
      } else {
        delete node.exclusiveMaximum;
      }
    }
  });
}

/**
 * Convert Draft-06 schema features to Draft-07
 *
 * @param {Object} schema - Schema to convert (mutated in place)
 */
function convertDraft6ToDraft7(schema) {
  // Draft-06 and Draft-07 are very similar
  // Main differences are in keywords that aren't commonly used
  // Most Draft-06 schemas are compatible with Draft-07

  walkSchema(schema, (node) => {
    // Draft-06 "propertyNames" is compatible with Draft-07
    // Draft-06 "contains" is compatible with Draft-07
    // Draft-06 "const" is compatible with Draft-07
    // No major conversions needed
  });
}

/**
 * Walk through a schema tree and apply a function to each node
 *
 * @param {Object} schema - Schema to walk
 * @param {Function} fn - Function to apply to each node
 */
function walkSchema(schema, fn) {
  if (!schema || typeof schema !== 'object') {
    return;
  }

  // Apply function to current node
  fn(schema);

  // Recurse into properties
  if (schema.properties) {
    Object.values(schema.properties).forEach(prop => walkSchema(prop, fn));
  }

  // Recurse into items
  if (schema.items) {
    if (Array.isArray(schema.items)) {
      schema.items.forEach(item => walkSchema(item, fn));
    } else {
      walkSchema(schema.items, fn);
    }
  }

  // Recurse into patternProperties
  if (schema.patternProperties) {
    Object.values(schema.patternProperties).forEach(prop => walkSchema(prop, fn));
  }

  // Recurse into additionalProperties
  if (typeof schema.additionalProperties === 'object') {
    walkSchema(schema.additionalProperties, fn);
  }

  // Recurse into definitions
  if (schema.definitions) {
    Object.values(schema.definitions).forEach(def => walkSchema(def, fn));
  }

  // Recurse into allOf, anyOf, oneOf
  ['allOf', 'anyOf', 'oneOf'].forEach(key => {
    if (Array.isArray(schema[key])) {
      schema[key].forEach(subschema => walkSchema(subschema, fn));
    }
  });

  // Recurse into not
  if (schema.not) {
    walkSchema(schema.not, fn);
  }

  // Recurse into if/then/else (Draft-07 feature)
  if (schema.if) walkSchema(schema.if, fn);
  if (schema.then) walkSchema(schema.then, fn);
  if (schema.else) walkSchema(schema.else, fn);
}

/**
 * Dereference $ref pointers in schema
 *
 * @param {Object} schema - Schema with $ref pointers
 * @returns {Promise<Object>} Dereferenced schema
 */
async function dereferenceSchema(schema) {
  try {
    const dereferencer = new Dereferencer(schema);
    const dereferenced = await dereferencer.resolve();
    return dereferenced;
  } catch (error) {
    throw new Error(`Failed to dereference schema: ${error.message}`);
  }
}

module.exports = {
  normalizeSchema,
  detectDraft,
  dereferenceSchema,
  walkSchema
};
