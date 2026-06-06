# Code Packaging Tests
# Tests for archive_file data source creation and ZIP file generation

# Test 1: archive_file data source created per function
mock_provider "aws" {}

run "archive_file_per_function" {
  command = plan

  variables {
    config_path      = "tests/fixtures/valid-minimal.yml"
    lambda_code_path = "tests/fixtures"
  }

  assert {
    condition     = length(data.archive_file.lambda_code) == length(local.functions_with_defaults)
    error_message = "Should create one archive_file data source per function"
  }
}

# Test 2: ZIP output path in .terraform/ directory
run "zip_output_path_correct" {
  command = plan

  variables {
    config_path      = "tests/fixtures/valid-minimal.yml"
    lambda_code_path = "tests/fixtures"
  }

  assert {
    condition = alltrue([
      for key, archive in data.archive_file.lambda_code :
      can(regex("^\\.?/?\\.terraform/lambda-.*\\.zip$", archive.output_path))
    ])
    error_message = "ZIP files should be stored in .terraform/ directory with pattern lambda-{function_key}.zip"
  }
}

# Test 3: source_code_hash populated correctly
run "source_code_hash_populated" {
  command = plan

  variables {
    config_path      = "tests/fixtures/valid-minimal.yml"
    lambda_code_path = "tests/fixtures"
  }

  assert {
    condition = alltrue([
      for key, archive in data.archive_file.lambda_code :
      archive.output_base64sha256 != null && archive.output_base64sha256 != ""
    ])
    error_message = "source_code_hash should be populated for all function archives"
  }
}

# Test 4: Multiple functions get separate ZIP files
run "multiple_functions_separate_zips" {
  command = plan

  variables {
    config_path      = "tests/fixtures/valid-full.yml"
    lambda_code_path = "tests/fixtures"
  }

  assert {
    condition = length(data.archive_file.lambda_code) > 1 && alltrue([
      for i, key1 in keys(data.archive_file.lambda_code) : alltrue([
        for j, key2 in keys(data.archive_file.lambda_code) :
        i == j || data.archive_file.lambda_code[key1].output_path != data.archive_file.lambda_code[key2].output_path
      ])
    ])
    error_message = "Each function should have its own unique ZIP file"
  }
}

# Test 5: Functionless configuration (no archives created)
run "functionless_no_archives" {
  command = plan

  variables {
    config_path      = "tests/fixtures/functionless.yml"
    lambda_code_path = "tests/fixtures"
  }

  assert {
    condition     = length(data.archive_file.lambda_code) == 0
    error_message = "Functionless configuration should create no archive_file data sources"
  }
}
