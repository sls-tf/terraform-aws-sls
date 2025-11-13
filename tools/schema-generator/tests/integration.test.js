/**
 * Integration tests for schema generator
 *
 * These tests verify the full pipeline from schema loading to file generation,
 * ensuring all components work together correctly.
 */

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const GENERATOR_BIN = path.join(__dirname, '../bin/schema-generator.js');
const SCHEMAS_DIR = path.join(__dirname, '../../../schemas/serverless-framework');
const TEST_OUTPUT_DIR = path.join(__dirname, '../test-output');

describe('Integration Tests', () => {
  beforeEach(() => {
    // Clean test output directory
    if (fs.existsSync(TEST_OUTPUT_DIR)) {
      fs.rmSync(TEST_OUTPUT_DIR, { recursive: true });
    }
    fs.mkdirSync(TEST_OUTPUT_DIR, { recursive: true });
  });

  afterEach(() => {
    // Clean up test output
    if (fs.existsSync(TEST_OUTPUT_DIR)) {
      fs.rmSync(TEST_OUTPUT_DIR, { recursive: true });
    }
  });

  describe('End-to-End Generation Pipeline', () => {
    test('should generate valid Terraform HCL from schema to file', () => {
      // Run generator for v3 schema
      const result = execSync(
        `node ${GENERATOR_BIN} --schema-version=3 --output-dir=${TEST_OUTPUT_DIR}`,
        { encoding: 'utf8', cwd: path.join(__dirname, '..') }
      );

      // Verify output file exists
      const outputFile = path.join(TEST_OUTPUT_DIR, 'validation-v3.tf');
      expect(fs.existsSync(outputFile)).toBe(true);

      // Read generated content
      const content = fs.readFileSync(outputFile, 'utf8');

      // Verify file header
      expect(content).toContain('AUTO-GENERATED FILE - DO NOT EDIT');
      expect(content).toContain('schema-generator v0.1.0');
      expect(content).toContain('Serverless Framework v3');

      // Verify validation structure
      expect(content).toContain('locals {');
      expect(content).toContain('v3_validation_errors = concat(');

      // Verify some expected validation rules
      expect(content).toContain('Required field');
      expect(content).toContain('Enum validation');
      expect(content).toContain('Type validation');
    });

    test('should generate files for all versions with --schema-version=all', () => {
      execSync(
        `node ${GENERATOR_BIN} --schema-version=all --output-dir=${TEST_OUTPUT_DIR}`,
        { encoding: 'utf8', cwd: path.join(__dirname, '..') }
      );

      // Verify all version files exist
      expect(fs.existsSync(path.join(TEST_OUTPUT_DIR, 'validation-v2.tf'))).toBe(true);
      expect(fs.existsSync(path.join(TEST_OUTPUT_DIR, 'validation-v3.tf'))).toBe(true);
      expect(fs.existsSync(path.join(TEST_OUTPUT_DIR, 'validation-v4.tf'))).toBe(true);
      expect(fs.existsSync(path.join(TEST_OUTPUT_DIR, 'validation-common.tf'))).toBe(true);
    });

    test('should complete generation in under 5 seconds', () => {
      const startTime = Date.now();

      execSync(
        `node ${GENERATOR_BIN} --schema-version=all --output-dir=${TEST_OUTPUT_DIR}`,
        { encoding: 'utf8', cwd: path.join(__dirname, '..') }
      );

      const duration = (Date.now() - startTime) / 1000;

      expect(duration).toBeLessThan(5);
      console.log(`      Generation completed in ${duration.toFixed(2)}s`);
    });
  });

  describe('Error Handling', () => {
    test('should handle invalid schema version gracefully', () => {
      expect(() => {
        execSync(
          `node ${GENERATOR_BIN} --schema-version=99 --output-dir=${TEST_OUTPUT_DIR}`,
          { encoding: 'utf8', cwd: path.join(__dirname, '..'), stdio: 'pipe' }
        );
      }).toThrow();
    });

    test('should handle missing output directory creation', () => {
      const deepOutputDir = path.join(TEST_OUTPUT_DIR, 'deep/nested/dir');

      execSync(
        `node ${GENERATOR_BIN} --schema-version=3 --output-dir=${deepOutputDir}`,
        { encoding: 'utf8', cwd: path.join(__dirname, '..') }
      );

      expect(fs.existsSync(path.join(deepOutputDir, 'validation-v3.tf'))).toBe(true);
    });
  });

  describe('Version-Specific Constraints', () => {
    test('should generate different validation rules for v2 vs v3', () => {
      execSync(
        `node ${GENERATOR_BIN} --schema-version=all --output-dir=${TEST_OUTPUT_DIR}`,
        { encoding: 'utf8', cwd: path.join(__dirname, '..') }
      );

      const v2Content = fs.readFileSync(path.join(TEST_OUTPUT_DIR, 'validation-v2.tf'), 'utf8');
      const v3Content = fs.readFileSync(path.join(TEST_OUTPUT_DIR, 'validation-v3.tf'), 'utf8');

      // Count validation rules
      const v2Rules = (v2Content.match(/# Required field:|# Enum validation:|# Type validation:/g) || []).length;
      const v3Rules = (v3Content.match(/# Required field:|# Enum validation:|# Type validation:/g) || []).length;

      // v3 should have more validation rules than v2
      expect(v3Rules).toBeGreaterThan(v2Rules);

      console.log(`      v2 rules: ${v2Rules}, v3 rules: ${v3Rules}`);
    });

    test('should include v4-specific features in v4 validation', () => {
      execSync(
        `node ${GENERATOR_BIN} --schema-version=4 --output-dir=${TEST_OUTPUT_DIR}`,
        { encoding: 'utf8', cwd: path.join(__dirname, '..') }
      );

      const v4Content = fs.readFileSync(path.join(TEST_OUTPUT_DIR, 'validation-v4.tf'), 'utf8');

      // v4 should have more runtimes than older versions
      expect(v4Content).toContain('nodejs20.x');
      expect(v4Content).toContain('python3.12');
    });
  });

  describe('Configuration File Support', () => {
    test('should respect custom configuration file', () => {
      // Create custom config
      const customConfig = path.join(TEST_OUTPUT_DIR, 'custom-config.yml');
      fs.writeFileSync(customConfig, `
included_paths:
  - '/properties/service'
excluded_paths:
  - '/properties/provider'
  - '/properties/functions'
`);

      execSync(
        `node ${GENERATOR_BIN} --schema-version=3 --output-dir=${TEST_OUTPUT_DIR} --config=${customConfig}`,
        { encoding: 'utf8', cwd: path.join(__dirname, '..') }
      );

      const content = fs.readFileSync(path.join(TEST_OUTPUT_DIR, 'validation-v3.tf'), 'utf8');

      // Should have service validation
      expect(content).toContain('service');

      // Should have fewer rules since provider and functions are excluded
      const ruleCount = (content.match(/# Required field:|# Enum validation:|# Type validation:/g) || []).length;
      expect(ruleCount).toBeLessThan(20); // Significantly fewer than default 44
    });
  });

  describe('Terraform Compatibility', () => {
    test('should generate syntactically valid HCL', () => {
      execSync(
        `node ${GENERATOR_BIN} --schema-version=3 --output-dir=${TEST_OUTPUT_DIR}`,
        { encoding: 'utf8', cwd: path.join(__dirname, '..') }
      );

      // Try to format with terraform fmt (if available)
      try {
        const result = execSync(
          `terraform fmt -check ${TEST_OUTPUT_DIR}/validation-v3.tf`,
          { encoding: 'utf8', stdio: 'pipe' }
        );
        // If terraform fmt succeeds without changes, file is properly formatted
      } catch (error) {
        // If terraform is not installed, skip this check
        if (!error.message.includes('terraform: not found') &&
            !error.message.includes('command not found')) {
          // Format and check if it's at least valid HCL
          execSync(`terraform fmt ${TEST_OUTPUT_DIR}/validation-v3.tf`, { stdio: 'pipe' });
        }
      }

      // Basic HCL syntax checks
      const content = fs.readFileSync(path.join(TEST_OUTPUT_DIR, 'validation-v3.tf'), 'utf8');

      // Count braces - should be balanced
      const openBraces = (content.match(/{/g) || []).length;
      const closeBraces = (content.match(/}/g) || []).length;
      expect(openBraces).toBe(closeBraces);

      // Count brackets - should be balanced
      const openBrackets = (content.match(/\[/g) || []).length;
      const closeBrackets = (content.match(/\]/g) || []).length;
      expect(openBrackets).toBe(closeBrackets);

      // Should not contain HTML entities (escaping issue)
      expect(content).not.toContain('&quot;');
      expect(content).not.toContain('&#x3D;');
      expect(content).not.toContain('&lt;');
      expect(content).not.toContain('&gt;');
    });
  });

  describe('Reproducibility', () => {
    test('should generate identical output for same inputs', () => {
      // Generate twice
      execSync(
        `node ${GENERATOR_BIN} --schema-version=3 --output-dir=${TEST_OUTPUT_DIR}`,
        { encoding: 'utf8', cwd: path.join(__dirname, '..') }
      );

      const firstContent = fs.readFileSync(path.join(TEST_OUTPUT_DIR, 'validation-v3.tf'), 'utf8');

      // Remove and regenerate
      fs.unlinkSync(path.join(TEST_OUTPUT_DIR, 'validation-v3.tf'));

      execSync(
        `node ${GENERATOR_BIN} --schema-version=3 --output-dir=${TEST_OUTPUT_DIR}`,
        { encoding: 'utf8', cwd: path.join(__dirname, '..') }
      );

      const secondContent = fs.readFileSync(path.join(TEST_OUTPUT_DIR, 'validation-v3.tf'), 'utf8');

      // Content should be identical (except for timestamp)
      const firstWithoutTimestamp = firstContent.replace(/Generated: .+/g, 'Generated: TIMESTAMP');
      const secondWithoutTimestamp = secondContent.replace(/Generated: .+/g, 'Generated: TIMESTAMP');

      expect(firstWithoutTimestamp).toBe(secondWithoutTimestamp);
    });
  });
});
