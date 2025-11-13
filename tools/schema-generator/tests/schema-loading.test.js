/**
 * Tests for schema loading functionality
 */

const fs = require('fs');
const path = require('path');

describe('Schema Loading', () => {
  const schemasDir = path.join(__dirname, '../../../schemas/serverless-framework');

  test('v2.x schema file exists', () => {
    const schemaPath = path.join(schemasDir, 'v2.x.json');
    expect(fs.existsSync(schemaPath)).toBe(true);
  });

  test('v3.x schema file exists', () => {
    const schemaPath = path.join(schemasDir, 'v3.x.json');
    expect(fs.existsSync(schemaPath)).toBe(true);
  });

  test('v4.x schema file exists', () => {
    const schemaPath = path.join(schemasDir, 'v4.x.json');
    expect(fs.existsSync(schemaPath)).toBe(true);
  });

  test('v2.x schema is valid JSON', () => {
    const schemaPath = path.join(schemasDir, 'v2.x.json');
    const content = fs.readFileSync(schemaPath, 'utf8');
    expect(() => JSON.parse(content)).not.toThrow();
  });

  test('v3.x schema is valid JSON', () => {
    const schemaPath = path.join(schemasDir, 'v3.x.json');
    const content = fs.readFileSync(schemaPath, 'utf8');
    expect(() => JSON.parse(content)).not.toThrow();
  });

  test('v4.x schema is valid JSON', () => {
    const schemaPath = path.join(schemasDir, 'v4.x.json');
    const content = fs.readFileSync(schemaPath, 'utf8');
    expect(() => JSON.parse(content)).not.toThrow();
  });

  test('v2.x schema has required properties', () => {
    const schemaPath = path.join(schemasDir, 'v2.x.json');
    const schema = JSON.parse(fs.readFileSync(schemaPath, 'utf8'));

    expect(schema).toHaveProperty('$schema');
    expect(schema).toHaveProperty('type');
    expect(schema).toHaveProperty('properties');
    expect(schema.type).toBe('object');
  });

  test('v3.x schema conforms to Draft-07', () => {
    const schemaPath = path.join(schemasDir, 'v3.x.json');
    const schema = JSON.parse(fs.readFileSync(schemaPath, 'utf8'));

    expect(schema.$schema).toContain('draft-07');
  });
});
