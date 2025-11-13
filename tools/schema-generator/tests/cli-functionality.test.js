/**
 * Tests for CLI functionality
 */

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const CLI_PATH = path.join(__dirname, '../bin/schema-generator.js');
const TEST_OUTPUT_DIR = path.join(__dirname, '../.test-output');

// Clean up test output before tests
beforeAll(() => {
  if (fs.existsSync(TEST_OUTPUT_DIR)) {
    fs.rmSync(TEST_OUTPUT_DIR, { recursive: true });
  }
});

// Clean up test output after tests
afterAll(() => {
  if (fs.existsSync(TEST_OUTPUT_DIR)) {
    fs.rmSync(TEST_OUTPUT_DIR, { recursive: true });
  }
});

describe('CLI Execution', () => {
  test('CLI shows help with --help flag', () => {
    const output = execSync(`node ${CLI_PATH} --help`, { encoding: 'utf8' });

    expect(output).toContain('Usage:');
    expect(output).toContain('--schema-version');
    expect(output).toContain('--output-dir');
    expect(output).toContain('--config');
    expect(output).toContain('--full');
  });

  test('CLI shows version with --version flag', () => {
    const output = execSync(`node ${CLI_PATH} --version`, { encoding: 'utf8' });

    expect(output).toMatch(/\d+\.\d+\.\d+/); // Matches semantic version
  });

  test('CLI generates v3 validation file', () => {
    const output = execSync(
      `node ${CLI_PATH} --schema-version=3 --output-dir=${TEST_OUTPUT_DIR}`,
      { encoding: 'utf8' }
    );

    expect(output).toContain('Schema Generator');
    expect(output).toContain('Processing Serverless Framework v3.x');
    expect(output).toContain('Generation complete');

    // Check file was created
    const outputFile = path.join(TEST_OUTPUT_DIR, 'validation-v3.tf');
    expect(fs.existsSync(outputFile)).toBe(true);

    // Check file content
    const content = fs.readFileSync(outputFile, 'utf8');
    expect(content).toContain('AUTO-GENERATED FILE');
    expect(content).toContain('v3_validation_errors');
    expect(content).toContain('locals {');
  });

  test('CLI creates output directory if not exists', () => {
    const newOutputDir = path.join(TEST_OUTPUT_DIR, 'nested/path');

    execSync(
      `node ${CLI_PATH} --schema-version=3 --output-dir=${newOutputDir}`,
      { encoding: 'utf8' }
    );

    expect(fs.existsSync(newOutputDir)).toBe(true);
    expect(fs.existsSync(path.join(newOutputDir, 'validation-v3.tf'))).toBe(true);
  });

  test('CLI exits with error code on invalid version', () => {
    expect(() => {
      execSync(
        `node ${CLI_PATH} --schema-version=99 --output-dir=${TEST_OUTPUT_DIR}`,
        { encoding: 'utf8', stdio: 'pipe' }
      );
    }).toThrow();
  });

  test('CLI generates all versions with --schema-version=all', () => {
    const output = execSync(
      `node ${CLI_PATH} --schema-version=all --output-dir=${TEST_OUTPUT_DIR}`,
      { encoding: 'utf8' }
    );

    expect(output).toContain('v2.x');
    expect(output).toContain('v3.x');
    expect(output).toContain('v4.x');

    // Check all files were created
    expect(fs.existsSync(path.join(TEST_OUTPUT_DIR, 'validation-v2.tf'))).toBe(true);
    expect(fs.existsSync(path.join(TEST_OUTPUT_DIR, 'validation-v3.tf'))).toBe(true);
    expect(fs.existsSync(path.join(TEST_OUTPUT_DIR, 'validation-v4.tf'))).toBe(true);
    expect(fs.existsSync(path.join(TEST_OUTPUT_DIR, 'validation-common.tf'))).toBe(true);
  });

  test('Generated file contains proper HCL structure', () => {
    execSync(
      `node ${CLI_PATH} --schema-version=3 --output-dir=${TEST_OUTPUT_DIR}`,
      { encoding: 'utf8' }
    );

    const content = fs.readFileSync(path.join(TEST_OUTPUT_DIR, 'validation-v3.tf'), 'utf8');

    // Check for proper HCL structure
    expect(content).toContain('locals {');
    expect(content).toMatch(/v3_validation_errors\s*=\s*concat\(/);
    expect(content).toContain('try(local.parsed_config');
    expect(content).toContain('] : []'); // Ternary pattern
  });

  test('Generated file includes metadata', () => {
    execSync(
      `node ${CLI_PATH} --schema-version=3 --output-dir=${TEST_OUTPUT_DIR}`,
      { encoding: 'utf8' }
    );

    const content = fs.readFileSync(path.join(TEST_OUTPUT_DIR, 'validation-v3.tf'), 'utf8');

    expect(content).toContain('AUTO-GENERATED FILE');
    expect(content).toContain('Generator:');
    expect(content).toContain('Schema Version:');
    expect(content).toContain('Generated:');
    expect(content).toMatch(/\d{4}-\d{2}-\d{2}/); // Date format
  });
});
