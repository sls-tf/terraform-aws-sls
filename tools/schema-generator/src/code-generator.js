/**
 * Code Generator
 *
 * Orchestrates template rendering and HCL code generation
 */

const fs = require('fs');
const path = require('path');
const Handlebars = require('handlebars');
const { execSync } = require('child_process');

// Template cache
const templateCache = new Map();

/**
 * Generate Terraform validation code from constraints
 *
 * @param {Object} constraints - Extracted constraints
 * @param {Object} options - Generation options
 * @param {string} options.schemaVersion - Schema version (2, 3, 4, or 'common')
 * @param {string} options.generatorVersion - Generator version
 * @param {string} options.outputPath - Output file path
 * @returns {string} Generated HCL code
 */
function generateValidationCode(constraints, options = {}) {
  const {
    schemaVersion = 'common',
    generatorVersion = '0.1.0',
    outputPath = null
  } = options;

  // Generate file header
  const header = renderTemplate('file-header', {
    generatorVersion,
    schemaVersion,
    timestamp: new Date().toISOString(),
    schemaPath: `schemas/serverless-framework/v${schemaVersion}.x.json`
  });

  // Generate validation expressions for each constraint type
  const validations = [];

  // Required field validations
  constraints.required.forEach(constraint => {
    const accessor = pathToAccessor(constraint.path, constraint.field);
    const validation = renderTemplate('required-field', {
      field: constraint.field,
      schemaPath: constraint.schemaPath,
      accessor: accessor,
      description: constraint.description
    });
    validations.push({
      description: `Required field: ${constraint.field}`,
      expression: validation
    });
  });

  // Enum validations
  constraints.enums.forEach(constraint => {
    const field = extractFieldName(constraint.path);
    const accessor = pathToAccessor(constraint.path);
    const allowedValues = constraint.values.join(', ');

    // Generate suggestion for common typos
    const suggestion = generateEnumSuggestion(constraint.values, field);

    const validation = renderTemplate('enum-validation', {
      field: field,
      schemaPath: constraint.schemaPath,
      accessor: accessor,
      values: constraint.values,
      allowedValues: allowedValues,
      suggestion: suggestion,
      description: constraint.description
    });
    validations.push({
      description: `Enum validation: ${field}`,
      expression: validation
    });
  });

  // Type validations
  constraints.types.forEach(constraint => {
    const field = extractFieldName(constraint.path);
    const accessor = pathToAccessor(constraint.path);
    const typeCheck = generateTypeCheck(constraint.type, accessor);

    const validation = renderTemplate('type-validation', {
      path: constraint.path,
      field: field,
      type: constraint.type,
      schemaPath: constraint.schemaPath,
      accessor: accessor,
      typeCheck: typeCheck,
      description: constraint.description
    });
    validations.push({
      description: `Type validation: ${field} (${constraint.type})`,
      expression: validation
    });
  });

  // Pattern validations
  constraints.patterns.forEach(constraint => {
    const field = extractFieldName(constraint.path);
    const accessor = pathToAccessor(constraint.path);

    const validation = renderTemplate('pattern-validation', {
      field: field,
      schemaPath: constraint.schemaPath,
      accessor: accessor,
      pattern: constraint.pattern,
      description: constraint.description
    });
    validations.push({
      description: `Pattern validation: ${field}`,
      expression: validation
    });
  });

  // Range validations
  constraints.ranges.forEach(constraint => {
    const field = extractFieldName(constraint.path);
    const accessor = pathToAccessor(constraint.path);

    const validation = renderTemplate('range-validation', {
      field: field,
      schemaPath: constraint.schemaPath,
      accessor: accessor,
      minimum: constraint.minimum,
      maximum: constraint.maximum,
      exclusiveMinimum: constraint.exclusiveMinimum !== undefined,
      exclusiveMaximum: constraint.exclusiveMaximum !== undefined,
      description: constraint.description
    });
    validations.push({
      description: `Range validation: ${field}`,
      expression: validation
    });
  });

  // Generate main validation block
  const blockName = `v${schemaVersion}`;
  const validationBlock = renderTemplate('validation-block', {
    schemaVersion,
    blockName,
    validations
  });

  // Combine header and validation block
  const code = header + '\n' + validationBlock;

  // Format with terraform fmt if requested
  if (outputPath) {
    return formatTerraform(code);
  }

  return code;
}

/**
 * Convert JSON pointer path to Terraform accessor
 *
 * @param {string} path - JSON pointer path (e.g., '#/properties/provider/properties/runtime')
 * @param {string} field - Optional field name for required fields
 * @returns {string} Terraform accessor (e.g., '.provider.runtime')
 */
function pathToAccessor(path, field = null) {
  // Remove # prefix and /properties/ segments
  let cleanPath = path.replace(/^#/, '').replace(/\/properties\//g, '.');

  // Remove patternProperties and their regex patterns
  // Example: /patternProperties/^.*$/ becomes nothing (skip the dynamic key)
  cleanPath = cleanPath.replace(/\/patternProperties\/[^/]+/g, '');

  // Remove JSON Schema constraint paths (items, oneOf, allOf, etc.)
  cleanPath = cleanPath.replace(/\/(items|oneOf|anyOf|allOf)\/\d+/g, '');

  // Remove trailing constraint keywords
  cleanPath = cleanPath.replace(/\/(enum|type|required|pattern|minimum|maximum)$/g, '');

  // Clean up multiple dots and slashes
  cleanPath = cleanPath.replace(/\/+/g, '.').replace(/\.+/g, '.');

  // Remove leading and trailing dots
  cleanPath = cleanPath.replace(/^\.+|\.+$/g, '');

  // Add field if provided (for required field validations)
  if (field) {
    cleanPath = cleanPath ? `${cleanPath}.${field}` : field;
  }

  // Ensure leading dot for accessor
  return cleanPath ? '.' + cleanPath : '';
}

/**
 * Extract field name from path
 *
 * @param {string} path - JSON pointer path
 * @returns {string} Field name
 */
function extractFieldName(path) {
  const parts = path.split('/');
  return parts[parts.length - 1] || 'field';
}

/**
 * Generate type check expression for Terraform
 *
 * @param {string} type - JSON Schema type
 * @param {string} accessor - Terraform accessor path
 * @returns {string} Type check expression
 */
function generateTypeCheck(type, accessor) {
  const value = `try(local.parsed_config${accessor}, null)`;

  switch (type) {
    case 'string':
      return `can(tostring(${value}))`;
    case 'number':
      return `can(tonumber(${value}))`;
    case 'boolean':
      return `can(tobool(${value}))`;
    case 'object':
      return `can(keys(${value}))`;
    case 'array':
      return `can(length(${value}))`;
    default:
      return 'true'; // Unknown types pass
  }
}

/**
 * Generate helpful suggestion for enum validation errors
 *
 * @param {Array} values - Allowed enum values
 * @param {string} field - Field name
 * @returns {string} Suggestion text or empty string
 */
function generateEnumSuggestion(values, field) {
  // Common runtime typos
  if (field === 'runtime' && values.some(v => v.includes('nodejs'))) {
    return 'Common typo: use \\"nodejs18.x\\" not \\"node18.x\\"';
  }

  return '';
}

/**
 * Render a Handlebars template
 *
 * @param {string} templateName - Template name (without .hbs extension)
 * @param {Object} data - Template data
 * @returns {string} Rendered template
 */
function renderTemplate(templateName, data) {
  // Check cache
  if (templateCache.has(templateName)) {
    const template = templateCache.get(templateName);
    return template(data);
  }

  // Load template from file
  const templatePath = path.join(__dirname, '../templates', `${templateName}.hbs`);

  if (!fs.existsSync(templatePath)) {
    throw new Error(`Template not found: ${templatePath}`);
  }

  const templateSource = fs.readFileSync(templatePath, 'utf8');
  const template = Handlebars.compile(templateSource);

  // Cache for reuse
  templateCache.set(templateName, template);

  return template(data);
}

/**
 * Format generated code with terraform fmt
 *
 * @param {string} code - Code to format
 * @returns {string} Formatted code
 */
function formatTerraform(code) {
  try {
    // Write to temp file
    const tempFile = path.join(__dirname, '../.temp-format.tf');
    fs.writeFileSync(tempFile, code, 'utf8');

    // Run terraform fmt
    execSync(`terraform fmt ${tempFile}`, { stdio: 'pipe' });

    // Read formatted content
    const formatted = fs.readFileSync(tempFile, 'utf8');

    // Clean up temp file
    fs.unlinkSync(tempFile);

    return formatted;
  } catch (error) {
    console.warn('Warning: terraform fmt failed, returning unformatted code');
    return code;
  }
}

/**
 * Clear template cache
 */
function clearTemplateCache() {
  templateCache.clear();
}

module.exports = {
  generateValidationCode,
  pathToAccessor,
  extractFieldName,
  generateTypeCheck,
  renderTemplate,
  formatTerraform,
  clearTemplateCache
};
