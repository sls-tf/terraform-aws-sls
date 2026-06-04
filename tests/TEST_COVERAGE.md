# Test Coverage Documentation

## Overview
**Total Tests: 28 (100% passing)**
- Initial Development Tests: 18
- Strategic Gap Coverage Tests: 10

## Test Breakdown by Category

### 1. YAML Parsing Tests (5 tests)
**File:** `tests/yaml_parsing.tftest.hcl`

| Test Name | Coverage |
|-----------|----------|
| `valid_minimal_yaml` | Valid YAML parsing with minimal serverless.yml |
| `invalid_yaml_syntax` | Invalid YAML syntax error handling with friendly messages |
| `file_not_found` | File not found error handling |
| `empty_file` | Empty file handling |
| `valid_full_yaml` | Valid YAML with full configuration (functions, custom, resources) |

**Coverage:** ✅ File reading, YAML parsing, error handling, friendly error messages

---

### 2. Schema Validation Tests (6 tests)
**File:** `tests/validation.tftest.hcl`

| Test Name | Coverage |
|-----------|----------|
| `missing_service_field` | Missing required field: service |
| `missing_provider_field` | Missing required field: provider |
| `invalid_provider_name` | Invalid provider.name (not "aws") |
| `missing_runtime_strict` | Missing runtime at both provider and function levels (strict validation) |
| `multiple_validation_errors` | Multiple validation errors collected together |
| `functionless_config_valid` | Functionless configuration acceptance |

**Coverage:** ✅ Required field validation, strict runtime validation, error collection, functionless configs

---

### 3. Default Application Tests (7 tests)
**File:** `tests/defaults.tftest.hcl`

| Test Name | Coverage |
|-----------|----------|
| `stage_defaults_to_dev` | Stage defaults to "dev" |
| `region_defaults_to_us_east_1` | Region defaults to "us-east-1" |
| `memory_defaults_to_1024` | MemorySize defaults to 1024 |
| `timeout_defaults_to_6` | Timeout defaults to 6 |
| `runtime_no_default` | Runtime has NO default (strict validation) |
| `function_inherits_defaults` | Function inherits provider defaults |
| `function_overrides_precedence` | Function overrides take precedence |

**Coverage:** ✅ Serverless Framework default values, function inheritance, override precedence

---

### 4. Gap Coverage Tests (10 tests)
**File:** `tests/gap_coverage.tftest.hcl`

| Test Name | Coverage |
|-----------|----------|
| `framework_version_2x` | Framework version 2.x validation |
| `framework_version_4x` | Framework version 4.x validation |
| `framework_version_invalid` | Invalid framework version rejection (1.x) |
| `provider_runtime_inheritance_all` | Provider runtime inheritance to all functions |
| `memory_boundary_min` | Memory boundary value: minimum (128 MB) |
| `memory_boundary_max` | Memory boundary value: maximum (10240 MB) |
| `timeout_boundary_min` | Timeout boundary value: minimum (1 second) |
| `timeout_boundary_max` | Timeout boundary value: maximum (900 seconds) |
| `complex_function_mixed` | Complex function configurations with mixed defaults/overrides |
| `complete_valid_config_e2e` | Complete valid configuration end-to-end (all sections) |

**Coverage:** ✅ Framework version compatibility, boundary value validation, runtime inheritance, complex scenarios, end-to-end workflows

---

## Coverage by Feature Area

### ✅ YAML Parsing (Complete)
- Valid YAML parsing
- Invalid syntax error handling
- File reading errors
- Empty file handling
- Friendly error messages
- Full configuration parsing

### ✅ Schema Validation (Complete)
- Required field validation (service, provider, provider.name)
- Strict runtime validation (provider OR function level)
- Optional field validation (frameworkVersion, memorySize, timeout)
- Function-level validation (handler, memorySize, timeout)
- Error collection pattern (all errors at once)
- Functionless configuration support

### ✅ Default Application (Complete)
- Provider-level defaults (stage, region, memorySize, timeout)
- Function-level default inheritance
- Function override precedence
- No default for runtime (strict mode)
- Region override warning (non-blocking)

### ✅ Framework Version Compatibility (Complete)
- Serverless Framework 2.x support
- Serverless Framework 3.x support (tested in valid_full_yaml)
- Serverless Framework 4.x support
- Invalid version rejection

### ✅ Boundary Value Validation (Complete)
- Memory: 128 MB (minimum)
- Memory: 10240 MB (maximum)
- Timeout: 1 second (minimum)
- Timeout: 900 seconds (maximum)

### ✅ Complex Scenarios (Complete)
- Mixed defaults and overrides across multiple functions
- Provider runtime inheritance to all functions
- Complete end-to-end configuration with all sections

### ✅ Output Generation (Covered by existing tests)
- All 7 outputs tested via assertions in existing tests
- parsed_config, service_name, provider_config, functions
- custom, resources, package sections

---

## Intentional Gaps (Out of Scope)

The following areas are **intentionally not covered** as they are deferred to future roadmap items:

- **TypeScript Parsing** - Roadmap item #6
- **Variable Resolution** - Roadmap item #10
- **Schema Sync Tooling** - Roadmap item #13
- **Resource Provisioning** - Roadmap items #2-12 (Lambda, API Gateway, DynamoDB, etc.)
- **CloudFormation Intrinsics** - Future enhancement, not on current roadmap
- **Runtime Pattern Validation** - Not strictly required for parsing/validation
- **Region Validation** - Not strictly required for parsing/validation

---

## Test Execution

Run all tests:
```bash
terraform test
```

Run specific test file:
```bash
terraform test tests/yaml_parsing.tftest.hcl
terraform test tests/validation.tftest.hcl
terraform test tests/defaults.tftest.hcl
terraform test tests/gap_coverage.tftest.hcl
```

---

### Lambda Code Source Gating (regression — Issue B)
**File:** `tests/lambda_code_source.tftest.hcl`

| Test Name | Coverage |
|-----------|----------|
| `local_mode_archives_every_function` | `type = "local"` archives + size-validates every function; Lambdas use a local filename |
| `s3_mode_skips_archiving` | `type = "s3"` creates **zero** `archive_file`/size-validation resources; Lambdas deploy from S3 with the computed `s3_key` |
| `local_mode_single_function` | Single-function local config still archives (guards against an over-broad gate) |
| `functionless_no_archives_local` / `functionless_no_archives_s3` | No functions ⇒ no archives in either source mode |

**Coverage:** ✅ `var.lambda_code_source.type` gating of `data.archive_file.lambda_code`
and `null_resource.lambda_size_validation`. Pins the regression from commit
`9ecf8c8c`, where dropping the `if … == "local"` gate made S3-source consumers
fail `plan` trying to archive a non-existent `CodeUri` directory (report.md,
Issue B). Uses `mock_provider "aws"`, so it runs with neither LocalStack nor AWS
credentials.

---

## Test Standards Alignment

This test suite follows the user's testing standards from `.agent-os/standards/testing/test-writing.md`:

✅ **Minimal Test Approach**: 28 strategic tests (within 18-42 target range)
✅ **Test Only Core User Flows**: Focus on parsing, validation, defaults
✅ **Defer Edge Case Testing**: Only critical edge cases (boundary values)
✅ **Test Behavior, Not Implementation**: Tests verify what code does, not how
✅ **Clear Test Names**: Descriptive names explaining what's tested
✅ **Fast Execution**: All tests run in seconds

---

## Success Metrics ✅

- ✅ Module successfully parses valid serverless.yml files
- ✅ Invalid configurations produce comprehensive, actionable error messages
- ✅ All validation errors collected and displayed together (not one at a time)
- ✅ Defaults match Serverless Framework specification exactly
- ✅ Functionless configurations validate successfully
- ✅ Region override produces warning but doesn't halt execution
- ✅ All outputs properly populated for downstream consumption
- ✅ 28 strategic tests cover critical workflows
- ✅ Module ready for integration with roadmap items #2-12
