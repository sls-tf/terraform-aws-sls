# Lambda Code Source Gating Tests
#
# Regression coverage for Issue B (report.md, 2026-06-04): the
# data.archive_file.lambda_code and null_resource.lambda_size_validation
# for_each expressions must be gated on var.lambda_code_source.type == "local".
# Commit 9ecf8c8c ("Fix archive_file for_each: use functions_with_defaults
# directly") dropped that gate, so an S3-source consumer tried to archive a
# per-function CodeUri directory that is never checked out in the git-ops/S3
# flow, failing plan with "could not archive missing directory".
#
# These are pure plan-time for_each logic tests, so they use a mock AWS provider
# and need neither LocalStack nor real AWS credentials. The archive provider is
# left real: in local mode it zips tests/fixtures (which exists), and in S3 mode
# the gate makes its for_each empty so it never touches the filesystem.

mock_provider "aws" {}

# ---------------------------------------------------------------------------
# Local mode (default): archives and size validation are created per function.
# ---------------------------------------------------------------------------

run "local_mode_archives_every_function" {
  command = plan

  variables {
    config_path      = "tests/fixtures/valid-full.yml"
    lambda_code_path = "tests/fixtures"
    # lambda_code_source defaults to { type = "local" }
  }

  assert {
    condition     = length(data.archive_file.lambda_code) == length(local.functions_with_defaults)
    error_message = "Local mode should create one archive_file per function"
  }

  assert {
    condition     = length(null_resource.lambda_size_validation) == length(local.functions_with_defaults)
    error_message = "Local mode should create one size-validation resource per function"
  }

  assert {
    condition     = alltrue([for f in aws_lambda_function.functions : f.filename != null && f.s3_bucket == null])
    error_message = "Local mode Lambdas should deploy from a local filename, not S3"
  }
}

# ---------------------------------------------------------------------------
# S3 mode: archives and size validation are gated OUT entirely. This is the
# exact regression from Issue B — without the gate, plan fails trying to
# archive a CodeUri directory that does not exist in the S3 flow.
# ---------------------------------------------------------------------------

run "s3_mode_skips_archiving" {
  command = plan

  variables {
    config_path      = "tests/fixtures/valid-full.yml"
    lambda_code_path = "tests/fixtures"
    lambda_code_source = {
      type       = "s3"
      bucket     = "my-artefacts-bucket"
      key_prefix = "lambdas"
      sha        = "deadbeefcafe"
    }
  }

  assert {
    condition     = length(data.archive_file.lambda_code) == 0
    error_message = "S3 mode must create zero archive_file data sources (Issue B regression)"
  }

  assert {
    condition     = length(null_resource.lambda_size_validation) == 0
    error_message = "S3 mode must create zero size-validation resources (Issue B regression)"
  }

  assert {
    condition     = alltrue([for f in aws_lambda_function.functions : f.s3_bucket == "my-artefacts-bucket" && f.filename == null])
    error_message = "S3 mode Lambdas should deploy from S3, not a local filename"
  }

  assert {
    condition     = alltrue([for f in aws_lambda_function.functions : can(regex("^lambdas/.*/deadbeefcafe\\.zip$", f.s3_key))])
    error_message = "S3 mode should compute s3_key from key_prefix/artefact/sha"
  }
}

# ---------------------------------------------------------------------------
# Single-function local mode still archives (guards against an over-broad gate).
# ---------------------------------------------------------------------------

run "local_mode_single_function" {
  command = plan

  variables {
    config_path      = "tests/fixtures/valid-minimal.yml"
    lambda_code_path = "tests/fixtures"
  }

  assert {
    condition     = length(data.archive_file.lambda_code) == 1
    error_message = "Single-function local config should create exactly one archive"
  }
}

# ---------------------------------------------------------------------------
# Functionless config: no functions, therefore no archives in either mode.
# ---------------------------------------------------------------------------

run "functionless_no_archives_local" {
  command = plan

  variables {
    config_path      = "tests/fixtures/functionless.yml"
    lambda_code_path = "tests/fixtures"
  }

  assert {
    condition     = length(data.archive_file.lambda_code) == 0
    error_message = "Functionless config should create no archives in local mode"
  }
}

run "functionless_no_archives_s3" {
  command = plan

  variables {
    config_path      = "tests/fixtures/functionless.yml"
    lambda_code_path = "tests/fixtures"
    lambda_code_source = {
      type       = "s3"
      bucket     = "my-artefacts-bucket"
      key_prefix = "lambdas"
      sha        = "deadbeefcafe"
    }
  }

  assert {
    condition     = length(data.archive_file.lambda_code) == 0
    error_message = "Functionless config should create no archives in S3 mode"
  }
}
