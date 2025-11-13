/**
 * Tests for template rendering and code generation
 */

const {
  generateValidationCode,
  pathToAccessor,
  extractFieldName,
  generateTypeCheck,
  renderTemplate
} = require('../src/code-generator');

describe('Path Conversion', () => {
  test('pathToAccessor converts simple path', () => {
    const result = pathToAccessor('#/properties/service');
    expect(result).toBe('.service');
  });

  test('pathToAccessor converts nested path', () => {
    const result = pathToAccessor('#/properties/provider/properties/runtime');
    expect(result).toBe('.provider.runtime');
  });

  test('pathToAccessor handles required field', () => {
    const result = pathToAccessor('#/properties/provider', 'runtime');
    expect(result).toBe('.provider.runtime');
  });

  test('extractFieldName gets last segment', () => {
    const result = extractFieldName('#/properties/provider/properties/runtime');
    expect(result).toBe('runtime');
  });
});

describe('Type Check Generation', () => {
  test('generateTypeCheck for string', () => {
    const result = generateTypeCheck('string', '.service');
    expect(result).toContain('tostring');
  });

  test('generateTypeCheck for number', () => {
    const result = generateTypeCheck('number', '.timeout');
    expect(result).toContain('tonumber');
  });

  test('generateTypeCheck for boolean', () => {
    const result = generateTypeCheck('boolean', '.versionFunctions');
    expect(result).toContain('tobool');
  });

  test('generateTypeCheck for object', () => {
    const result = generateTypeCheck('object', '.provider');
    expect(result).toContain('keys');
  });

  test('generateTypeCheck for array', () => {
    const result = generateTypeCheck('array', '.functions');
    expect(result).toContain('length');
  });
});

describe('Template Rendering', () => {
  test('renderTemplate for file-header', () => {
    const result = renderTemplate('file-header', {
      generatorVersion: '0.1.0',
      schemaVersion: '3',
      timestamp: '2025-10-28T12:00:00.000Z',
      schemaPath: 'schemas/serverless-framework/v3.x.json'
    });

    expect(result).toContain('AUTO-GENERATED FILE');
    expect(result).toContain('v0.1.0');
    expect(result).toContain('v3');
    expect(result).toContain('2025-10-28');
  });

  test('renderTemplate for required-field', () => {
    const result = renderTemplate('required-field', {
      field: 'service',
      schemaPath: '#/properties/service',
      accessor: '.service',
      description: 'Service name'
    });

    expect(result).toContain('service');
    expect(result).toContain('try(local.parsed_config.service, null)');
    expect(result).toContain('Required field');
  });

  test('renderTemplate for enum-validation', () => {
    const result = renderTemplate('enum-validation', {
      field: 'runtime',
      schemaPath: '#/properties/provider/properties/runtime',
      accessor: '.provider.runtime',
      values: ['nodejs18.x', 'python3.11'],
      allowedValues: 'nodejs18.x, python3.11'
    });

    expect(result).toContain('runtime');
    expect(result).toContain('nodejs18.x');
    expect(result).toContain('python3.11');
    expect(result).toContain('contains');
  });
});

describe('Code Generation', () => {
  test('generateValidationCode with required constraint', () => {
    const constraints = {
      required: [{
        path: '#',
        field: 'service',
        schemaPath: '#/required'
      }],
      types: [],
      enums: [],
      patterns: [],
      ranges: [],
      conditionals: []
    };

    const code = generateValidationCode(constraints, {
      schemaVersion: '3',
      generatorVersion: '0.1.0'
    });

    expect(code).toContain('AUTO-GENERATED FILE');
    expect(code).toContain('v3');
    expect(code).toContain('service');
    expect(code).toContain('validation_errors');
  });

  test('generateValidationCode with enum constraint', () => {
    const constraints = {
      required: [],
      types: [],
      enums: [{
        path: '#/properties/provider/properties/runtime',
        values: ['nodejs18.x', 'python3.11'],
        schemaPath: '#/properties/provider/properties/runtime/enum'
      }],
      patterns: [],
      ranges: [],
      conditionals: []
    };

    const code = generateValidationCode(constraints, {
      schemaVersion: '3',
      generatorVersion: '0.1.0'
    });

    expect(code).toContain('nodejs18.x');
    expect(code).toContain('python3.11');
    expect(code).toContain('contains');
  });

  test('generateValidationCode with type constraint', () => {
    const constraints = {
      required: [],
      types: [{
        path: '#/properties/service',
        type: 'string',
        schemaPath: '#/properties/service/type'
      }],
      enums: [],
      patterns: [],
      ranges: [],
      conditionals: []
    };

    const code = generateValidationCode(constraints, {
      schemaVersion: '3',
      generatorVersion: '0.1.0'
    });

    expect(code).toContain('string');
    expect(code).toContain('tostring');
  });

  test('generateValidationCode creates valid HCL structure', () => {
    const constraints = {
      required: [{
        path: '#',
        field: 'service',
        schemaPath: '#/required'
      }],
      types: [],
      enums: [],
      patterns: [],
      ranges: [],
      conditionals: []
    };

    const code = generateValidationCode(constraints, {
      schemaVersion: '3',
      generatorVersion: '0.1.0'
    });

    // Check for proper HCL structure
    expect(code).toContain('locals {');
    expect(code).toContain('concat(');
    expect(code).toContain('[] # Empty list');
    expect(code).toContain(')'); // Closing concat
    expect(code).toContain('}'); // Closing locals
  });
});
