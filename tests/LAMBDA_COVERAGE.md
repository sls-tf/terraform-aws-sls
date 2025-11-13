# Lambda Function Translation - Test Coverage

This document outlines the test coverage for Roadmap Item #2: Lambda Function Translation.

## Test Summary

**Total Tests: 28**
- Provider Setup: 4 tests
- Code Packaging: 5 tests
- IAM Roles: 6 tests
- Lambda Resources: 8 tests
- Lambda Outputs: 5 tests

**Status: ✅ All tests passing (56 total including core module tests)**

## Test Files

### tests/provider_setup.tftest.hcl (4 tests)
Tests for archive provider initialization and lambda_code_path variable:

1. **archive_provider_available** - Verifies archive provider initializes successfully
2. **lambda_code_path_non_empty** - Validates that lambda_code_path cannot be empty string
3. **lambda_code_path_default** - Confirms default value is "." (current directory)
4. **lambda_code_path_custom** - Tests that custom paths are accepted

**Coverage:** Provider requirements, variable validation

### tests/code_packaging.tftest.hcl (5 tests)
Tests for archive_file data source creation and ZIP file generation:

1. **archive_file_per_function** - One archive_file created per function
2. **zip_output_path_correct** - ZIP files stored in .terraform/ directory
3. **source_code_hash_populated** - Source code hash generated for change detection
4. **multiple_functions_separate_zips** - Each function gets unique ZIP file
5. **functionless_no_archives** - No archives created for functionless configs

**Coverage:** Code packaging, ZIP generation, change detection

### tests/iam_roles.tftest.hcl (6 tests)
Tests for IAM execution role creation and policy attachments:

1. **one_role_per_function** - One IAM role created per function
2. **role_trust_policy_correct** - Trust policy allows lambda.amazonaws.com
3. **basic_execution_policy_attached** - AWSLambdaBasicExecutionPolicy attached
4. **role_naming_convention** - Roles follow {service}-{stage}-{function}-role pattern
5. **functionless_no_roles** - No roles created for functionless configs
6. **multiple_functions_multiple_roles** - Each function gets unique role

**Coverage:** IAM role creation, trust policies, managed policy attachments, naming conventions

### tests/lambda_resources.tftest.hcl (8 tests)
Tests for aws_lambda_function resource generation:

1. **lambda_function_per_definition** - One Lambda function per definition
2. **lambda_naming_convention** - Functions follow {service}-{stage}-{function} pattern
3. **lambda_properties_mapped** - Runtime, handler, memory, timeout correctly mapped
4. **lambda_description_optional** - Description mapped when present, null when absent
5. **lambda_has_source_code_hash** - Source code hash enables change detection
6. **lambda_references_code_package** - Functions reference correct ZIP files
7. **lambda_environment_conditional** - Environment block only when variables exist
8. **multiple_functions_different_configs** - Each function has unique configuration

**Coverage:** Lambda function creation, property mapping, environment variables, code references

### tests/lambda_outputs.tftest.hcl (5 tests)
Tests for Lambda function outputs:

1. **function_arns_output_populated** - function_arns map contains all functions
2. **function_names_output_populated** - function_names map contains all functions
3. **role_arns_output_populated** - role_arns map contains all roles
4. **invoke_arns_output_populated** - function_invoke_arns map contains all functions
5. **functionless_empty_output_maps** - Empty maps when no functions defined

**Coverage:** Output interface, map population, functionless scenarios

## Test Fixtures Used

- `tests/fixtures/valid-minimal.yml` - Single function with minimal configuration
- `tests/fixtures/valid-full.yml` - Multiple functions with different properties
- `tests/fixtures/functionless.yml` - Infrastructure-only configuration
- `tests/fixtures/missing-runtime.yml` - Validation test fixture
- `tests/fixtures/missing-service.yml` - Validation test fixture

## Coverage Areas

### ✅ Fully Covered
- Provider and variable setup
- Code packaging and ZIP generation
- IAM role creation with basic execution policy
- Lambda function resource generation
- Property mapping and inheritance
- Environment variable handling
- Output interface
- Functionless configurations
- Naming conventions
- Change detection via source code hashing

### ⚠️ Intentionally Not Covered (Out of Scope for #2)
- Custom IAM policies (roadmap #3)
- Event source integrations (roadmap #4-8)
- VPC configuration
- Lambda layers
- Versioning/aliases
- Dead letter queues
- Reserved/provisioned concurrency
- X-Ray tracing
- Individual function code paths
- Advanced packaging (package.patterns)

### 📋 Future Enhancements
- Integration tests with actual deployment (apply)
- Performance tests with large function counts
- Package size optimization tests
- Multi-region deployment scenarios

## Testing Strategy

Following minimal test approach as per project standards:
- **2-8 focused tests per task group** during development
- **Run only newly written tests** at each stage (not entire suite)
- **Maximum 10 additional tests** for integration/gap filling
- **Total: 28 tests** for Lambda translation feature
- **Focus on critical behaviors**, not exhaustive coverage
- **Skip edge cases** unless business-critical

## Test Execution

Run all Lambda translation tests:
```bash
terraform test -filter=tests/provider_setup.tftest.hcl \
               -filter=tests/code_packaging.tftest.hcl \
               -filter=tests/iam_roles.tftest.hcl \
               -filter=tests/lambda_resources.tftest.hcl \
               -filter=tests/lambda_outputs.tftest.hcl
```

Run all tests (including core module):
```bash
terraform test
```

## Integration with Roadmap Items

The Lambda translation outputs are designed for consumption by:
- **Roadmap #3 (IAM Role & Policy Management)**: `role_arns` for custom policy attachment
- **Roadmap #4 (API Gateway Integration)**: `function_invoke_arns` for API Gateway permissions
- **Roadmap #5-8 (Event Sources)**: `function_arns` for event source mappings

## Validation Integration

Lambda resources are only created when:
1. Configuration parsing succeeds (`local.parsed_config != null`)
2. All validation errors pass (`length(local.validation_errors) == 0`)
3. Functions are defined (`local.functions_with_defaults` non-empty)

This ensures validation happens before resource creation, maintaining the validation-first design from roadmap #1.

## Success Criteria ✅

All acceptance criteria from tasks.md met:
- ✅ 28 tests written across 5 test files
- ✅ All tests passing
- ✅ Archive provider initialization tested
- ✅ Code packaging generates ZIPs with correct naming
- ✅ IAM roles created with proper trust policy
- ✅ Lambda functions created with all properties
- ✅ Environment variables handled correctly
- ✅ Outputs populated for downstream integration
- ✅ Functionless configurations supported
- ✅ Naming conventions validated
- ✅ Change detection via source_code_hash verified
