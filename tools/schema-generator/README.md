# Schema Generator

Automated tooling to generate Terraform validation code from Serverless Framework JSON schemas.

## Overview

The schema generator tool automatically creates Terraform HCL validation code from the official Serverless Framework JSON schemas. This ensures that validation rules stay synchronized with schema evolution across Framework versions 2.x, 3.x, and 4.x.

### Key Features

- **Multi-Version Support**: Generates validation for Serverless Framework v2.x, v3.x, and v4.x
- **Automated Synchronization**: CI/CD workflows keep schemas and validation up-to-date
- **Configurable Coverage**: Control which schema paths are validated
- **Terraform Native**: Generates idiomatic Terraform HCL code
- **Comprehensive Validation**: Extracts required fields, types, enums, patterns, and ranges
- **Clear Error Messages**: Validation errors include schema paths and helpful suggestions

## Installation

### Prerequisites

- Node.js 14.0.0 or higher
- npm or yarn
- Terraform 1.0+ (for validation)

### Setup

```bash
# From repository root
cd tools/schema-generator

# Install dependencies
npm install

# Verify installation
npm test
```

## Usage

### Quick Start

Generate validation files for all Serverless Framework versions:

```bash
# From repository root
npm run generate:validation
```

This creates:
- `generated/validation-v2.tf` - Validation for Serverless Framework v2.x
- `generated/validation-v3.tf` - Validation for Serverless Framework v3.x
- `generated/validation-v4.tf` - Validation for Serverless Framework v4.x
- `generated/validation-common.tf` - Common validation structure

### Command-Line Options

```bash
node tools/schema-generator/bin/schema-generator.js [options]
```

**Options:**

| Option | Description | Default | Required |
|--------|-------------|---------|----------|
| `--schema-version <version>` | Schema version to generate (2, 3, 4, or all) | - | Yes |
| `--output-dir <path>` | Output directory for generated files | `generated/` | No |
| `--config <path>` | Configuration file path | `tools/schema-generator/config.yml` | No |
| `--full` | Generate all schema paths, ignoring config | false | No |
| `--help` | Display help information | - | No |
| `--version` | Display version information | - | No |

### Examples

**Generate validation for specific version:**
```bash
npm run generate:validation:v3
```

**Generate with custom output directory:**
```bash
node tools/schema-generator/bin/schema-generator.js \
  --schema-version=all \
  --output-dir=./custom-output
```

**Generate all paths (ignore config):**
```bash
node tools/schema-generator/bin/schema-generator.js \
  --schema-version=3 \
  --full
```

**Use custom configuration:**
```bash
node tools/schema-generator/bin/schema-generator.js \
  --schema-version=all \
  --config=./custom-config.yml
```

## Configuration

### Configuration File Format

The configuration file (`config.yml`) controls which schema paths are validated:

```yaml
# Include these schema paths in validation
included_paths:
  - '/properties/service'
  - '/properties/provider'
  - '/properties/functions'

# Exclude these schema paths from validation
excluded_paths:
  - '/properties/plugins'
  - '/properties/package'
```

**Path Format:**
- Use JSON pointer notation
- Prefix with `/` (e.g., `/properties/service`)
- Wildcards supported: `/properties/functions/*`

### Default Configuration

By default, the generator validates:
- `service` - Service configuration
- `provider` - Provider settings (AWS, Azure, etc.)
- `functions` - Lambda function definitions

And excludes:
- `plugins` - Serverless plugins
- `package` - Package configuration

### Adding New Schema Paths

As new roadmap features are implemented, add their schema paths:

```yaml
included_paths:
  - '/properties/service'
  - '/properties/provider'
  - '/properties/functions'
  - '/properties/resources'    # NEW: CloudFormation resources
  - '/properties/custom'       # NEW: Custom variables
```

Then regenerate:
```bash
npm run generate:validation
```

See [MAINTENANCE.md](MAINTENANCE.md#adding-new-schema-paths) for detailed instructions.

## Generated Validation

### Validation Types

The generator extracts and creates validation for:

1. **Required Fields**: Ensures mandatory fields are present
2. **Type Constraints**: Validates field types (string, number, boolean, object, array)
3. **Enum Values**: Validates against allowed value lists
4. **Pattern Matching**: Validates strings against regex patterns
5. **Range Constraints**: Validates numeric min/max bounds
6. **Conditional Logic**: Handles if/then/else schema constraints

### Example Generated Code

```hcl
# Required field: name
# Schema path: #/properties/service/required
try(local.parsed_config.service.name, null) == null ? [
  "Required field 'name' is missing. See: https://www.serverless.com/framework/docs/providers/aws/guide/serverless.yml#name (Schema: #/properties/service/required)"
] : []

# Enum validation: runtime
# Allowed values: nodejs18.x, nodejs16.x, python3.11, ...
try(local.parsed_config.provider.runtime, null) != null && !contains(["nodejs18.x", "nodejs16.x", "python3.11"], try(local.parsed_config.provider.runtime, "")) ? [
  "Invalid runtime. Must be one of: [nodejs18.x, nodejs16.x, python3.11], got: '${try(local.parsed_config.provider.runtime, "")}'. Common typo: use \"nodejs18.x\" not \"node18.x\". (Schema: #/properties/provider/properties/runtime/enum)"
] : []
```

### Integration with Module

The generated validation files integrate with the main module's validation pattern:

```hcl
# In your main Terraform code
locals {
  # Load version-specific validation
  validation_errors = concat(
    local.v3_validation_errors,  # From generated/validation-v3.tf
    local.manual_validation_errors  # Hand-written validations
  )
}

# Fail if validation errors exist
resource "null_resource" "validation" {
  count = length(local.validation_errors) > 0 ? 1 : 0

  provisioner "local-exec" {
    command = <<-EOT
      echo "Configuration validation failed:"
      ${join("\n", local.validation_errors)}
    EOT
  }
}
```

## Development

### Project Structure

```
tools/schema-generator/
├── src/                      # Source code
│   ├── schema-loader.js      # Schema file loading and caching
│   ├── schema-normalizer.js  # Draft-04/06 to Draft-07 conversion
│   ├── constraint-extractor.js # Extract validation constraints
│   ├── config-loader.js      # Configuration file handling
│   └── code-generator.js     # HCL code generation
├── templates/                # Handlebars templates
│   ├── file-header.hbs
│   ├── validation-block.hbs
│   ├── required-field.hbs
│   ├── type-validation.hbs
│   ├── enum-validation.hbs
│   ├── pattern-validation.hbs
│   └── range-validation.hbs
├── tests/                    # Test suite
│   ├── schema-loading.test.js
│   ├── schema-processing.test.js
│   ├── template-rendering.test.js
│   ├── cli-functionality.test.js
│   └── integration.test.js
├── bin/                      # CLI entrypoint
│   └── schema-generator.js
├── config.yml                # Default configuration
├── package.json
└── README.md
```

### Running Tests

```bash
# Run all tests
npm test

# Run specific test file
npm test -- tests/integration.test.js

# Run with coverage
npm test -- --coverage

# Run in watch mode
npm test -- --watch
```

**Test Coverage:** 59 tests covering:
- Schema loading and validation (8 tests)
- Schema processing and extraction (17 tests)
- Template rendering (16 tests)
- CLI functionality (8 tests)
- Integration workflows (10 tests)

### Template Customization

Templates are located in `templates/` and use Handlebars syntax:

```handlebars
# Required field: {{{field}}}
# Schema path: {{{schemaPath}}}
try(local.parsed_config{{{accessor}}}, null) == null ? [
  "Required field '{{{field}}}' is missing. (Schema: {{{schemaPath}}})"
] : []
```

**Important:**
- Use triple braces `{{{ }}}` to prevent HTML escaping
- All variables must be properly escaped for Terraform syntax
- Test changes with `npm test` before committing

### Adding New Constraint Types

To add support for new JSON Schema constraints:

1. **Update constraint-extractor.js:**
```javascript
function extractNewConstraint(schema, basePath = '') {
  // Implementation
}
```

2. **Create template:**
```handlebars
// templates/new-constraint.hbs
```

3. **Update code-generator.js:**
```javascript
function generateNewConstraintValidation(constraint) {
  return renderTemplate('new-constraint', constraint);
}
```

4. **Add tests:**
```javascript
test('should extract new constraint', () => {
  // Test implementation
});
```

## CI/CD Integration

The schema generator includes automated workflows:

### Drift Detection

**Workflow:** `.github/workflows/validate-generated-code.yml`

- Runs on all pull requests
- Detects manual edits to generated files
- Validates Terraform formatting
- Checks performance (< 10 seconds)

### Schema Updates

**Workflow:** `.github/workflows/schema-update.yml`

- Runs weekly (Mondays 9 AM UTC)
- Checks for new Serverless Framework releases
- Updates schemas automatically
- Creates pull requests with changes

See [MAINTENANCE.md](MAINTENANCE.md#cicd-workflows) for details.

## Troubleshooting

### Common Issues

**Issue: "Schema file not found"**

```bash
# Verify schemas exist
ls -lh schemas/serverless-framework/

# Download if missing
cd schemas/serverless-framework
curl -o v3.x.json https://raw.githubusercontent.com/serverless/serverless/v3/lib/configSchema/schema.json
```

**Issue: "Invalid JSON in schema"**

```bash
# Validate JSON syntax
jq empty schemas/serverless-framework/v3.x.json
```

**Issue: "Template rendering error"**

Check template syntax in `templates/`. Common issues:
- Unbalanced braces `{{ }}` vs `{{{ }}}`
- Missing variables
- Invalid Handlebars syntax

**Issue: "Terraform fmt fails"**

```bash
# Format generated files
cd generated && terraform fmt .

# Check for syntax errors
terraform validate .
```

### Debug Mode

Enable verbose logging:

```bash
DEBUG=true npm run generate:validation
```

## Performance

**Targets:**
- Generation: < 5 seconds for all versions
- Validation overhead: < 100ms for typical configurations
- CI validation: < 30 seconds total

**Current Performance:**
- Full generation (v2, v3, v4): ~1.5 seconds
- Test suite: ~2 seconds (59 tests)

## Contributing

See [CONTRIBUTING-GENERATED-CODE.md](../../docs/CONTRIBUTING-GENERATED-CODE.md) for guidelines on:
- When to edit templates vs. generated files
- How to add new validation rules
- Testing requirements
- Code review process

## Support

- **Documentation:** [MAINTENANCE.md](MAINTENANCE.md)
- **Issues:** GitHub issues with `schema-generator` label
- **Schema Questions:** [Serverless Framework Docs](https://www.serverless.com/framework/docs/)

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 0.1.0 | 2025-10-28 | Initial release with v2.x, v3.x, v4.x support |

## License

Same as parent project.
