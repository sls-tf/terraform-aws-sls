/**
 * Tests for schema processing functionality
 */

const { normalizeSchema, detectDraft } = require('../src/schema-normalizer');
const { loadSchema, schemaExists } = require('../src/schema-loader');
const { extractConstraints, filterConstraints } = require('../src/constraint-extractor');
const { loadConfig, validateConfig } = require('../src/config-loader');

describe('Schema Normalization', () => {
  test('detectDraft identifies Draft-04', () => {
    const draftUrl = 'http://json-schema.org/draft-04/schema#';
    expect(detectDraft(draftUrl)).toBe(4);
  });

  test('detectDraft identifies Draft-07', () => {
    const draftUrl = 'http://json-schema.org/draft-07/schema#';
    expect(detectDraft(draftUrl)).toBe(7);
  });

  test('detectDraft defaults to 7 for unknown', () => {
    expect(detectDraft(null)).toBe(7);
    expect(detectDraft('http://example.com/schema')).toBe(7);
  });

  test('normalizeSchema converts Draft-04 to Draft-07', () => {
    const schema = {
      $schema: 'http://json-schema.org/draft-04/schema#',
      id: 'http://example.com/schema',
      type: 'object'
    };

    const normalized = normalizeSchema(schema);

    expect(normalized.$schema).toContain('draft-07');
    expect(normalized.$id).toBe('http://example.com/schema');
    expect(normalized.id).toBeUndefined();
  });
});

describe('Schema Loading', () => {
  test('schemaExists returns true for v2.x', () => {
    expect(schemaExists('2')).toBe(true);
  });

  test('schemaExists returns true for v3.x', () => {
    expect(schemaExists('3')).toBe(true);
  });

  test('loadSchema loads v3.x schema', async () => {
    const schema = await loadSchema('3');

    expect(schema).toBeDefined();
    expect(schema.type).toBe('object');
    expect(schema.properties).toBeDefined();
    expect(schema.properties.service).toBeDefined();
    expect(schema.properties.provider).toBeDefined();
  });

  test('loadSchema throws error for invalid version', async () => {
    await expect(loadSchema('99')).rejects.toThrow('Invalid schema version');
  });
});

describe('Constraint Extraction', () => {
  test('extractConstraints finds required fields', () => {
    const schema = {
      type: 'object',
      required: ['service', 'provider'],
      properties: {
        service: { type: 'string' },
        provider: { type: 'object' }
      }
    };

    const constraints = extractConstraints(schema);

    expect(constraints.required).toHaveLength(2);
    expect(constraints.required[0].field).toBe('service');
    expect(constraints.required[1].field).toBe('provider');
  });

  test('extractConstraints finds enum constraints', () => {
    const schema = {
      type: 'object',
      properties: {
        runtime: {
          type: 'string',
          enum: ['nodejs18.x', 'python3.11']
        }
      }
    };

    const constraints = extractConstraints(schema);

    expect(constraints.enums).toHaveLength(1);
    expect(constraints.enums[0].values).toEqual(['nodejs18.x', 'python3.11']);
  });

  test('extractConstraints finds type constraints', () => {
    const schema = {
      type: 'object',
      properties: {
        service: { type: 'string' },
        timeout: { type: 'number' }
      }
    };

    const constraints = extractConstraints(schema);

    expect(constraints.types.length).toBeGreaterThan(0);
    const stringType = constraints.types.find(t => t.type === 'string');
    const numberType = constraints.types.find(t => t.type === 'number');
    expect(stringType).toBeDefined();
    expect(numberType).toBeDefined();
  });

  test('filterConstraints respects include paths', () => {
    const constraints = {
      required: [
        { path: '#/properties/service', field: 'name' },
        { path: '#/properties/plugins', field: 'list' }
      ],
      types: [],
      enums: [],
      patterns: [],
      ranges: [],
      conditionals: []
    };

    const filtered = filterConstraints(
      constraints,
      ['/properties/service/*'],
      []
    );

    expect(filtered.required).toHaveLength(1);
    expect(filtered.required[0].path).toContain('service');
  });

  test('filterConstraints respects exclude paths', () => {
    const constraints = {
      required: [
        { path: '#/properties/service', field: 'name' },
        { path: '#/properties/plugins', field: 'list' }
      ],
      types: [],
      enums: [],
      patterns: [],
      ranges: [],
      conditionals: []
    };

    const filtered = filterConstraints(
      constraints,
      [],
      ['/properties/plugins/*']
    );

    expect(filtered.required).toHaveLength(1);
    expect(filtered.required[0].path).toContain('service');
  });
});

describe('Configuration Loading', () => {
  test('validateConfig accepts valid config', () => {
    const config = {
      included_paths: ['/properties/service'],
      excluded_paths: ['/properties/plugins']
    };

    expect(() => validateConfig(config)).not.toThrow();
  });

  test('validateConfig rejects non-array included_paths', () => {
    const config = {
      included_paths: 'not-an-array'
    };

    expect(() => validateConfig(config)).toThrow('must be an array');
  });

  test('validateConfig rejects paths not starting with /', () => {
    const config = {
      included_paths: ['properties/service']  // Missing leading /
    };

    expect(() => validateConfig(config)).toThrow('must start with');
  });

  test('loadConfig returns defaults when file not found', () => {
    const config = loadConfig('/nonexistent/config.yml');

    expect(config).toBeDefined();
    expect(config.included_paths).toBeDefined();
    expect(config.excluded_paths).toBeDefined();
  });
});
