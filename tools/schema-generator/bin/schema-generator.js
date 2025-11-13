#!/usr/bin/env node

/**
 * Schema Generator CLI
 *
 * Generates Terraform validation code from Serverless Framework JSON schemas
 */

const fs = require('fs');
const path = require('path');
const yargs = require('yargs/yargs');
const { hideBin } = require('yargs/helpers');
const chalk = require('chalk');
const packageJson = require('../package.json');

// Import generator modules
const { loadSchema } = require('../src/schema-loader');
const { extractConstraints, filterConstraints, getConstraintStats } = require('../src/constraint-extractor');
const { loadConfig } = require('../src/config-loader');
const { generateValidationCode } = require('../src/code-generator');

// Parse command line arguments
const argv = yargs(hideBin(process.argv))
  .version(packageJson.version)
  .usage('Usage: $0 [options]')
  .option('schema-version', {
    alias: 'v',
    type: 'string',
    description: 'Serverless Framework version to generate validation for',
    choices: ['2', '3', '4', 'all'],
    demandOption: true
  })
  .option('output-dir', {
    alias: 'o',
    type: 'string',
    description: 'Output directory for generated files',
    default: 'generated'
  })
  .option('config', {
    alias: 'c',
    type: 'string',
    description: 'Path to configuration file',
    default: 'tools/schema-generator/config.yml'
  })
  .option('full', {
    alias: 'f',
    type: 'boolean',
    description: 'Generate validation for all schema paths (ignore config)',
    default: false
  })
  .example('$0 --schema-version=3', 'Generate validation for Serverless Framework v3.x')
  .example('$0 --schema-version=all --output-dir=./output', 'Generate validation for all versions')
  .example('$0 -v 3 --full', 'Generate full validation for v3.x (ignore config)')
  .help('h')
  .alias('h', 'help')
  .epilogue('For more information, see: tools/schema-generator/README.md')
  .argv;

// Main execution
async function main() {
  const startTime = Date.now();

  try {
    console.log(chalk.blue.bold('Schema Generator v' + packageJson.version));
    console.log(chalk.gray('Generating Terraform validation from Serverless Framework schemas\n'));

    // Log configuration
    console.log(chalk.cyan('Configuration:'));
    console.log(chalk.gray(`  Schema version: ${argv.schemaVersion}`));
    console.log(chalk.gray(`  Output directory: ${argv.outputDir}`));
    console.log(chalk.gray(`  Config file: ${argv.config}`));
    console.log(chalk.gray(`  Full generation: ${argv.full ? 'yes' : 'no'}\n`));

    // Load configuration
    console.log(chalk.cyan('Loading configuration...'));
    const config = loadConfig(argv.config, { useDefaults: true });
    console.log(chalk.gray(`  Included paths: ${config.included_paths.length}`));
    console.log(chalk.gray(`  Excluded paths: ${config.excluded_paths.length}\n`));

    // Determine versions to generate
    const versions = argv.schemaVersion === 'all' ? ['2', '3', '4'] : [argv.schemaVersion];

    // Ensure output directory exists
    const outputDir = path.resolve(process.cwd(), argv.outputDir);
    if (!fs.existsSync(outputDir)) {
      fs.mkdirSync(outputDir, { recursive: true });
      console.log(chalk.gray(`Created output directory: ${outputDir}\n`));
    }

    // Generate validation for each version
    const results = [];
    for (const version of versions) {
      console.log(chalk.cyan(`Processing Serverless Framework v${version}.x...`));

      // Load schema
      console.log(chalk.gray('  Loading schema...'));
      const schema = await loadSchema(version, { normalize: true });

      // Extract constraints
      console.log(chalk.gray('  Extracting constraints...'));
      const allConstraints = extractConstraints(schema);

      // Filter constraints based on config (unless --full flag)
      const constraints = argv.full
        ? allConstraints
        : filterConstraints(allConstraints, config.included_paths, config.excluded_paths);

      // Get statistics
      const stats = getConstraintStats(constraints);
      console.log(chalk.gray(`  Found ${stats.total} validation rules`));
      console.log(chalk.gray(`    - Required: ${stats.required}`));
      console.log(chalk.gray(`    - Types: ${stats.types}`));
      console.log(chalk.gray(`    - Enums: ${stats.enums}`));
      console.log(chalk.gray(`    - Patterns: ${stats.patterns}`));
      console.log(chalk.gray(`    - Ranges: ${stats.ranges}`));

      // Generate code
      console.log(chalk.gray('  Generating Terraform code...'));
      const code = generateValidationCode(constraints, {
        schemaVersion: version,
        generatorVersion: packageJson.version
      });

      // Write to file
      const outputFile = path.join(outputDir, `validation-v${version}.tf`);
      fs.writeFileSync(outputFile, code, 'utf8');
      console.log(chalk.green(`  ✓ Generated ${outputFile}`));
      console.log(chalk.gray(`    ${stats.total} validation rules, ${code.split('\n').length} lines\n`));

      results.push({
        version,
        file: outputFile,
        rules: stats.total,
        lines: code.split('\n').length
      });
    }

    // Generate common validation file (constraints that apply to all versions)
    if (versions.length > 1) {
      console.log(chalk.cyan('Generating common validation...'));
      // For now, just create an empty common file with header
      const commonCode = `# AUTO-GENERATED FILE - DO NOT EDIT
#
# Common validation rules that apply to all Serverless Framework versions
#
# Generator: schema-generator v${packageJson.version}
# Generated: ${new Date().toISOString()}

locals {
  # Common validation errors (applicable to all versions)
  common_validation_errors = concat(
    # Add common validation rules here
    []
  )
}
`;
      const commonFile = path.join(outputDir, 'validation-common.tf');
      fs.writeFileSync(commonFile, commonCode, 'utf8');
      console.log(chalk.green(`  ✓ Generated ${commonFile}\n`));
    }

    // Summary
    const elapsedTime = ((Date.now() - startTime) / 1000).toFixed(2);
    console.log(chalk.green.bold('✓ Generation complete!'));
    console.log(chalk.gray(`\nSummary:`));
    results.forEach(result => {
      console.log(chalk.gray(`  v${result.version}: ${result.rules} rules, ${result.lines} lines → ${path.basename(result.file)}`));
    });
    console.log(chalk.gray(`\nCompleted in ${elapsedTime}s`));
    console.log(chalk.gray(`Output directory: ${outputDir}\n`));

    process.exit(0);

  } catch (error) {
    console.error(chalk.red('\n✗ Error:'), error.message);
    if (process.env.DEBUG) {
      console.error(chalk.gray(error.stack));
    }
    console.log(chalk.yellow('\nFor more information, run with DEBUG=1\n'));
    process.exit(1);
  }
}

// Run main function
main();
