# Schema Generator Maintenance Guide

This guide explains how to maintain and update the schema generator tool and its generated validation code.

## Table of Contents

- [Overview](#overview)
- [Manual Schema Updates](#manual-schema-updates)
- [Regenerating Validation Files](#regenerating-validation-files)
- [Reviewing Schema Update PRs](#reviewing-schema-update-prs)
- [Adding New Schema Paths](#adding-new-schema-paths)
- [Troubleshooting](#troubleshooting)
- [CI/CD Workflows](#cicd-workflows)

## Overview

The schema generator tool automatically creates Terraform validation code from Serverless Framework JSON schemas. This ensures validation rules stay synchronized with schema evolution across Framework versions 2.x, 3.x, and 4.x.

### Key Components

```
tools/schema-generator/
├── src/                    # Generator source code
│   ├── schema-loader.js
│   ├── schema-normalizer.js
│   ├── constraint-extractor.js
│   ├── config-loader.js
│   └── code-generator.js
├── templates/              # Handlebars templates for HCL generation
│   ├── file-header.hbs
│   ├── validation-block.hbs
│   ├── required-field.hbs
│   ├── type-validation.hbs
│   ├── enum-validation.hbs
│   ├── pattern-validation.hbs
│   └── range-validation.hbs
├── tests/                  # Test suite (49 tests)
├── bin/                    # CLI entrypoint
│   └── schema-generator.js
├── config.yml              # Path filtering configuration
└── package.json

schemas/serverless-framework/   # Vendored schemas
├── v2.x.json
├── v3.x.json
├── v4.x.json
└── README.md

generated/                      # Auto-generated validation code
├── validation-v2.tf
├── validation-v3.tf
├── validation-v4.tf
├── validation-common.tf
└── README.md
```

## Manual Schema Updates

### When to Update Manually

- Serverless Framework releases a major version update
- Schema changes are needed for urgent bug fixes
- Automated workflow fails or needs debugging
- Testing schema changes before automating

### Update Process

#### Step 1: Download Latest Schemas

```bash
# From repository root
cd schemas/serverless-framework

# Download latest schemas
# v2.x
curl -o v2.x.json https://raw.githubusercontent.com/serverless/serverless/v2/lib/configSchema/schema.json

# v3.x
curl -o v3.x.json https://raw.githubusercontent.com/serverless/serverless/v3/lib/configSchema/schema.json

# v4.x
curl -o v4.x.json https://raw.githubusercontent.com/serverless/serverless/main/lib/configSchema/schema.json
```

#### Step 2: Verify Schema Validity

```bash
# Check JSON syntax
jq empty v2.x.json v3.x.json v4.x.json

# Compare with previous versions
diff -u <(git show HEAD:schemas/serverless-framework/v3.x.json) v3.x.json
```

#### Step 3: Update README

```bash
# Edit schemas/serverless-framework/README.md
# Update:
# - Last Updated date
# - Schema version numbers
# - Any notes about changes
```

#### Step 4: Regenerate Validation Files

```bash
# From repository root
npm run generate:validation

# Or for specific version
npm run generate:validation:v3
```

#### Step 5: Review Changes

```bash
# Check diff in generated files
git diff generated/

# Verify Terraform syntax
cd generated && terraform fmt -check .

# Run tests
cd tools/schema-generator && npm test
```

#### Step 6: Commit Changes

```bash
git add schemas/serverless-framework/ generated/
git commit -m "Update schemas to Serverless Framework v3.x.x

- Updated v3.x schema from v3.38.0 to v3.39.0
- Regenerated validation files
- Added 3 new validation rules for Lambda function URLs"
```

## Regenerating Validation Files

### Full Regeneration (All Versions)

```bash
npm run generate:validation
```

This generates:
- `generated/validation-v2.tf` (36 rules)
- `generated/validation-v3.tf` (44 rules)
- `generated/validation-v4.tf` (64 rules)
- `generated/validation-common.tf`

### Version-Specific Regeneration

```bash
# v2.x only
npm run generate:validation:v2

# v3.x only
npm run generate:validation:v3

# v4.x only
npm run generate:validation:v4
```

### Troubleshooting Regeneration

**Issue: "Schema file not found"**
```bash
# Verify schema files exist
ls -lh schemas/serverless-framework/
```

**Issue: "Invalid JSON in schema"**
```bash
# Validate JSON syntax
jq empty schemas/serverless-framework/v3.x.json
```

**Issue: "Template rendering error"**
```bash
# Check template syntax
# Templates are in tools/schema-generator/templates/
# Common issues: unbalanced braces, missing variables
```

**Issue: "Terraform fmt check fails"**
```bash
# Format generated files
cd generated && terraform fmt .

# If still failing, check for invalid HCL syntax
terraform validate .
```

## Reviewing Schema Update PRs

Automated schema update PRs are created by the `schema-update.yml` workflow. Here's how to review them effectively:

### 1. Check Automated Validations

✅ Verify all GitHub Actions checks pass:
- Generated code validation
- Terraform formatting
- Generator tests (49 tests)
- Performance check (< 10 seconds)

### 2. Review Schema Changes

```bash
# Checkout the PR branch
gh pr checkout <PR_NUMBER>

# Review schema diffs
git diff origin/main schemas/serverless-framework/
```

**Look for:**
- New required fields (breaking changes)
- Removed enum values (breaking changes)
- Changed type constraints
- New properties or features

### 3. Review Generated Validation Changes

```bash
# Check validation rule changes
git diff origin/main generated/
```

**Key checks:**
- Are error messages clear and helpful?
- Do new validation rules make sense?
- Are schema paths correctly referenced?

### 4. Test Locally

```bash
# Run full test suite
cd tools/schema-generator && npm test

# Test with sample configurations
# Create test files in tests/fixtures/
# Run validation manually to verify behavior
```

### 5. Assess Breaking Changes

**Low Risk:**
- New optional properties
- Additional enum values
- Documentation changes
- Bug fixes in validation logic

**Medium Risk:**
- Changed default values
- Modified validation patterns
- New validation rules for existing fields

**High Risk:**
- New required fields
- Removed enum values
- Changed type constraints
- Renamed properties

### 6. Merge Decision

✅ **Safe to merge:**
- All checks pass
- No breaking changes
- Error messages are clear
- Tests cover new validation rules

⚠️ **Needs discussion:**
- Breaking changes detected
- Significant validation logic changes
- Performance regressions

❌ **Do not merge:**
- Tests failing
- Invalid generated HCL
- Breaks existing valid configurations

## Adding New Schema Paths

As new roadmap features are implemented, you may need to validate additional schema paths.

### Step 1: Update Configuration

Edit `tools/schema-generator/config.yml`:

```yaml
included_paths:
  - '#/properties/service'
  - '#/properties/provider'
  - '#/properties/functions'
  - '#/properties/resources'        # NEW: Add resources validation
  - '#/properties/custom'           # NEW: Add custom section validation

excluded_paths:
  - '#/properties/plugins'
  - '#/properties/package'
```

**Path Format:**
- Use JSON pointer notation
- Prefix with `#` (root reference)
- Use `/properties/` for object properties
- Example: `#/properties/provider/properties/runtime`

**Wildcard Support:**
```yaml
included_paths:
  - '#/properties/functions/*'      # All function properties
```

### Step 2: Regenerate Validation

```bash
npm run generate:validation
```

### Step 3: Review Changes

```bash
# Check diff
git diff generated/

# Count new validation rules
grep -c "# Required field:" generated/validation-v3.tf
grep -c "# Enum validation:" generated/validation-v3.tf
```

### Step 4: Add Tests

If adding significant new validation, add test fixtures:

```bash
# Create test fixtures
cat > tests/fixtures/custom-valid.yml <<EOF
service: test-service
provider:
  name: aws
custom:
  myValue: 123
EOF

cat > tests/fixtures/custom-invalid.yml <<EOF
service: test-service
provider:
  name: aws
custom:
  myValue: "not a number"  # Will fail validation
EOF
```

### Step 5: Commit Changes

```bash
git add tools/schema-generator/config.yml generated/
git commit -m "Add validation for custom configuration section

- Updated config.yml to include #/properties/custom
- Regenerated validation files
- Added 5 new validation rules for custom section"
```

## Troubleshooting

### Generator Not Found

```bash
# Verify npm scripts are configured
grep generate:validation package.json

# Run directly if needed
node tools/schema-generator/bin/schema-generator.js --help
```

### Missing Dependencies

```bash
cd tools/schema-generator
npm install
```

### Tests Failing

```bash
# Run with detailed output
cd tools/schema-generator
npm test -- --verbose

# Run specific test file
npm test -- tests/template-rendering.test.js
```

### Performance Issues

```bash
# Profile generator execution
time npm run generate:validation

# Expected: < 5 seconds
# If slower: check schema size, template complexity
```

### Invalid HCL Generated

```bash
# Check specific error
cd generated
terraform fmt -check .

# Validate Terraform syntax
terraform validate .

# Common fixes:
# - Update templates to escape quotes properly
# - Use triple braces {{{ }}} in Handlebars
# - Check for unclosed strings or brackets
```

## CI/CD Workflows

### Drift Detection (`validate-generated-code.yml`)

**Triggers:**
- Pull requests
- Pushes to main/master
- Manual dispatch

**Purpose:**
- Detects manual edits to generated files
- Ensures generated code stays in sync
- Validates Terraform formatting
- Checks generator performance

**Fixing Drift:**
```bash
# Regenerate and commit
npm run generate:validation
git add generated/
git commit -m "Regenerate validation files"
```

### Schema Updates (`schema-update.yml`)

**Triggers:**
- Weekly schedule (Mondays 9 AM UTC)
- Manual dispatch

**Purpose:**
- Checks for new Serverless Framework releases
- Downloads updated schemas
- Regenerates validation files
- Creates pull request with changes

**Manual Trigger:**
```bash
# Via GitHub CLI
gh workflow run schema-update.yml

# Via GitHub UI
# Actions → Schema Update Detection → Run workflow
```

**Force Update:**
```bash
# Force regeneration even without schema changes
gh workflow run schema-update.yml -f force=true
```

## Best Practices

### DO ✅
- Always regenerate after template changes
- Review diffs before committing
- Run tests after regeneration
- Document significant schema changes
- Use configuration file for path filtering
- Keep templates simple and readable

### DON'T ❌
- Manually edit generated files
- Commit generated files without review
- Skip tests after regeneration
- Add validation for unimplemented features
- Hardcode paths in templates
- Ignore breaking schema changes

## Support

For issues or questions:
- **Documentation:** See [README.md](README.md)
- **Issues:** Create issue with `schema-generator` label
- **Schema Questions:** Refer to [Serverless Framework Docs](https://www.serverless.com/framework/docs/)
- **Terraform Questions:** See [Terraform HCL Syntax](https://developer.hashicorp.com/terraform/language/syntax)

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 0.1.0 | 2025-10-28 | Initial schema generator implementation |

---

**Last Updated:** 2025-10-28
