# Contributing to Generated Code

This guide explains how to work with auto-generated validation code in this project.

## Table of Contents

- [Overview](#overview)
- [Generated vs. Hand-Written Code](#generated-vs-hand-written-code)
- [When to Edit What](#when-to-edit-what)
- [Adding New Validation Rules](#adding-new-validation-rules)
- [Modifying Existing Validation](#modifying-existing-validation)
- [Testing Changes](#testing-changes)
- [Pull Request Guidelines](#pull-request-guidelines)

## Overview

This project uses a schema generator tool to automatically create Terraform validation code from Serverless Framework JSON schemas. This approach ensures:

✅ Validation stays synchronized with Serverless Framework evolution
✅ Consistency across all validation rules
✅ Comprehensive coverage of schema constraints
✅ Clear, helpful error messages

## Generated vs. Hand-Written Code

### Generated Code (DO NOT EDIT DIRECTLY)

**Location:** `generated/`

**Files:**
- `generated/validation-v2.tf`
- `generated/validation-v3.tf`
- `generated/validation-v4.tf`
- `generated/validation-common.tf`

**Characteristics:**
- Contains `AUTO-GENERATED FILE - DO NOT EDIT` header
- Generated from JSON schemas
- Covers standard Serverless Framework validation
- Synchronized via CI/CD workflows

**How to modify:** Edit templates in `tools/schema-generator/templates/` and regenerate

### Hand-Written Code (EDIT FREELY)

**Location:** Root directory and `modules/`

**Files:**
- `variables.tf`
- `locals.tf`
- `main.tf`
- `outputs.tf`
- Custom validation logic not derived from schemas

**Characteristics:**
- Module-specific business logic
- Custom validation rules
- Integration glue code
- Resource definitions

**How to modify:** Edit directly and commit

### Quick Reference Table

| Task | Generated Code | Hand-Written Code |
|------|----------------|-------------------|
| Fix validation error message | ❌ Edit template | ✅ Edit directly |
| Add new constraint type | ❌ Update generator | ✅ Add to locals.tf |
| Change validation logic | ❌ Edit template | ✅ Edit directly |
| Fix typo in comment | ❌ Edit template | ✅ Edit directly |
| Add module resource | N/A | ✅ Add to main.tf |

## When to Edit What

### Scenario 1: Adding Validation for New Schema Property

**Example:** Add validation for `custom` configuration section

**Approach:** Configure generator

```bash
# 1. Edit configuration
vim tools/schema-generator/config.yml

# Add to included_paths:
included_paths:
  - '/properties/service'
  - '/properties/provider'
  - '/properties/functions'
  - '/properties/custom'          # NEW

# 2. Regenerate validation
npm run generate:validation

# 3. Review changes
git diff generated/

# 4. Commit if looks good
git add tools/schema-generator/config.yml generated/
git commit -m "Add validation for custom configuration section"
```

**Why this approach:** The schema already defines constraints for `custom`, the generator just needs to include it.

### Scenario 2: Adding Custom Validation Logic

**Example:** Validate that Lambda memory is a power of 2

**Approach:** Add to hand-written code

```hcl
# In locals.tf
locals {
  # Custom validation: Memory must be power of 2
  custom_memory_validation = [
    for fn_name, fn_config in local.functions :
    try(fn_config.memorySize, null) != null &&
    floor(log(fn_config.memorySize) / log(2)) != ceil(log(fn_config.memorySize) / log(2)) ?
      "Function '${fn_name}' memory ${fn_config.memorySize} is not a power of 2"
    : ""
  ]

  # Combine with generated validation
  all_validation_errors = concat(
    local.v3_validation_errors,      # Generated
    local.custom_memory_validation,  # Hand-written
    # ... other validations
  )
}
```

**Why this approach:** This is business logic not defined in the Serverless Framework schema.

### Scenario 3: Improving Error Messages

**Example:** Make enum error message more helpful

**Approach:** Edit template

```bash
# 1. Edit template
vim tools/schema-generator/templates/enum-validation.hbs

# Modify error message format
"Invalid {{{field}}}. Must be one of: [{{{allowedValues}}}].
Got: '${try(local.parsed_config{{{accessor}}}, "")}'.
{{#if suggestion}}{{{suggestion}}}.{{/if}}
See: https://example.com/docs/{{{field}}}"  # Added docs link

# 2. Regenerate
npm run generate:validation

# 3. Review and commit
git diff generated/
git add tools/schema-generator/templates/enum-validation.hbs generated/
git commit -m "Improve enum validation error messages with docs links"
```

**Why this approach:** The change should apply to all enum validations consistently.

### Scenario 4: Adding Validation for Unimplemented Feature

**Example:** Add validation for Step Functions definitions (not yet implemented in module)

**Approach:** Wait or add manually

**Option A (Recommended):** Wait until feature is implemented
```yaml
# Don't add to config.yml yet
# The module doesn't support Step Functions, so validation would be confusing
```

**Option B:** Add manual validation temporarily
```hcl
# In locals.tf - temporary until feature implemented
locals {
  step_functions_not_supported = try(local.parsed_config.stepFunctions, null) != null ? [
    "Step Functions are not yet supported. See roadmap item #15"
  ] : []
}
```

**Why this approach:** Avoid validating features the module doesn't support yet.

## Adding New Validation Rules

### From Schema (Recommended)

Most validation should come from schemas automatically:

1. **Check if path already in config:**
   ```bash
   grep -r "properties/yourFeature" tools/schema-generator/config.yml
   ```

2. **If missing, add to included_paths:**
   ```yaml
   included_paths:
     - '/properties/yourFeature'
   ```

3. **Regenerate and verify:**
   ```bash
   npm run generate:validation
   grep -A 5 "yourFeature" generated/validation-v3.tf
   ```

### Custom Logic (When Needed)

For validation not in schemas:

1. **Add to appropriate locals block:**
   ```hcl
   locals {
     custom_validation_name = [
       for item in local.items :
       condition ? "Error message" : ""
     ]
   }
   ```

2. **Include in error aggregation:**
   ```hcl
   locals {
     all_validation_errors = concat(
       local.v3_validation_errors,
       local.custom_validation_name,
       # ...
     )
   }
   ```

3. **Add tests:**
   ```hcl
   # tests/custom-validation.tftest.hcl
   run "test_custom_validation" {
     command = plan

     variables {
       serverless_config = file("${path.module}/fixtures/invalid-custom.yml")
     }

     assert {
       condition     = contains(local.all_validation_errors, "Expected error message")
       error_message = "Custom validation should detect invalid configuration"
     }
   }
   ```

## Modifying Existing Validation

### Changing Generated Validation

**Never edit generated files directly.** Instead:

1. **Identify the template:**
   ```bash
   # Find which template generates the validation
   grep -l "pattern you're looking for" tools/schema-generator/templates/*.hbs
   ```

2. **Edit the template:**
   ```bash
   vim tools/schema-generator/templates/the-template.hbs
   ```

3. **Regenerate:**
   ```bash
   npm run generate:validation
   ```

4. **Verify changes:**
   ```bash
   git diff generated/
   ```

5. **Test:**
   ```bash
   cd tools/schema-generator && npm test
   ```

### Changing Hand-Written Validation

Edit files directly:

```bash
vim locals.tf
# Make changes
terraform fmt .
git add locals.tf
git commit -m "Update custom validation logic"
```

## Testing Changes

### Testing Generator Changes

```bash
cd tools/schema-generator

# Run tests
npm test

# Run specific test
npm test -- tests/integration.test.js

# Verify output
npm run generate:validation
```

### Testing Terraform Validation

```bash
# Create test fixture
cat > tests/fixtures/test-case.yml <<EOF
service: test
provider:
  name: aws
  runtime: invalid-runtime  # Should fail validation
EOF

# Run test
terraform test tests/your-test.tftest.hcl
```

### Integration Testing

```bash
# Full module test
terraform init
terraform plan -var="serverless_config=$(cat test-config.yml)"
```

## Pull Request Guidelines

### For Generator Changes

**Title:** `feat(generator): Add support for X` or `fix(generator): Correct Y`

**Description should include:**
- What validation was added/changed
- Why the change was needed
- Before/after examples of generated code
- Test results

**Checklist:**
- [ ] Templates updated
- [ ] Tests pass (`npm test`)
- [ ] Validation regenerated (`npm run generate:validation`)
- [ ] Generated files committed
- [ ] No manual edits to generated files
- [ ] README or MAINTENANCE.md updated if needed

**Example:**
```markdown
## Summary
Add validation for Lambda function URLs configuration

## Changes
- Updated config.yml to include /properties/functions/properties/url
- Added 5 new validation rules for function URLs
- Updated enum-validation template to handle URL-specific enums

## Testing
- All 59 tests pass
- Generated validation catches invalid URL configurations
- Tested with fixtures/function-url-*.yml

## Generated Code Changes
```diff
+    # Required field: url.cors
+    try(local.parsed_config.functions.url.cors, null) == null ? [
+      "Function URL requires CORS configuration"
+    ] : []
```
```

### For Hand-Written Code Changes

**Title:** `feat: Add X` or `fix: Correct Y`

**Description should include:**
- What was changed
- Why it was needed
- How it was tested

**Checklist:**
- [ ] Code follows Terraform style
- [ ] Tests added/updated
- [ ] Tests pass
- [ ] Documentation updated

## Common Mistakes to Avoid

### ❌ DON'T: Edit generated files directly

```bash
# WRONG
vim generated/validation-v3.tf
# Made changes...
git commit -m "Fix validation"
```

**Why:** Changes will be overwritten on next generation. CI will fail.

### ✅ DO: Edit templates and regenerate

```bash
# CORRECT
vim tools/schema-generator/templates/enum-validation.hbs
npm run generate:validation
git add tools/schema-generator/templates/ generated/
git commit -m "Fix enum validation template"
```

### ❌ DON'T: Mix generated and manual validation in same file

```hcl
# WRONG - in generated/validation-v3.tf
locals {
  v3_validation_errors = concat(
    # ... generated rules ...
    # Custom validation I added manually
    local.my_custom_check,  # This will be overwritten!
  )
}
```

### ✅ DO: Keep manual validation in separate files

```hcl
# CORRECT - in locals.tf
locals {
  v3_validation_errors = # From generated file

  custom_validation_errors = [
    # My custom rules here
  ]

  all_errors = concat(
    local.v3_validation_errors,
    local.custom_validation_errors
  )
}
```

### ❌ DON'T: Commit without regenerating

```bash
# WRONG
vim tools/schema-generator/templates/type-validation.hbs
git add tools/schema-generator/templates/
git commit -m "Update template"
# Generated files are now out of sync!
```

### ✅ DO: Always regenerate after template changes

```bash
# CORRECT
vim tools/schema-generator/templates/type-validation.hbs
npm run generate:validation
git add tools/schema-generator/templates/ generated/
git commit -m "Update type validation template"
```

## Getting Help

- **Generator Issues:** See [schema-generator/README.md](../tools/schema-generator/README.md)
- **Maintenance:** See [schema-generator/MAINTENANCE.md](../tools/schema-generator/MAINTENANCE.md)
- **Questions:** Open GitHub issue with `question` label
- **Validation Errors:** See [VALIDATION.md](VALIDATION.md)

## Summary

**Golden Rules:**

1. 🚫 **Never edit files in `generated/` directly**
2. ✅ **Edit templates, regenerate, commit all changes together**
3. 🧪 **Always run tests after changes**
4. 📝 **Keep custom validation in hand-written files**
5. 🔄 **Use CI to catch drift**

Following these guidelines ensures validation stays synchronized, consistent, and maintainable!
