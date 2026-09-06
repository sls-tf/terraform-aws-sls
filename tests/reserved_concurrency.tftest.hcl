# Reserved concurrency (aws_lambda_function.reserved_concurrent_executions).
#
# Surfaces: SAM Properties.ReservedConcurrentExecutions (with Globals.Function
# inheritance) and yaml functions.<name>.reservedConcurrency.
#
# The value carries two meanings that are easy to conflate:
#   - unset  -> leave the account's unreserved pool alone (provider default -1).
#               MUST stay null so brownfield functions import without a diff.
#   - 0      -> a real reservation of zero, i.e. the function cannot be invoked.
#               MUST NOT be read as "unset" (a coalesce on falsiness would).
# Both are asserted below; the 0 cases are the regression-prone ones.

mock_provider "aws" {}

# ---------------------------------------------------------------------------
# yaml (serverless-framework) format
# ---------------------------------------------------------------------------

run "yaml_reserved_concurrency" {
  command = plan

  variables {
    config_path      = "tests/fixtures/reserved-concurrency.yml"
    lambda_code_path = "tests/fixtures"
  }

  assert {
    condition     = aws_lambda_function.functions["capped"].reserved_concurrent_executions == 3
    error_message = "yaml reservedConcurrency: 3 should reach reserved_concurrent_executions, got ${jsonencode(aws_lambda_function.functions["capped"].reserved_concurrent_executions)}"
  }

  assert {
    condition     = aws_lambda_function.functions["disabled"].reserved_concurrent_executions == 0
    error_message = "yaml reservedConcurrency: 0 must be preserved as 0 (function disabled), got ${jsonencode(aws_lambda_function.functions["disabled"].reserved_concurrent_executions)}"
  }

  assert {
    condition     = aws_lambda_function.functions["uncapped"].reserved_concurrent_executions == null
    error_message = "A function with no reservedConcurrency must leave reserved_concurrent_executions null (unreserved), got ${jsonencode(aws_lambda_function.functions["uncapped"].reserved_concurrent_executions)}"
  }
}

# ---------------------------------------------------------------------------
# SAM format, including Globals.Function inheritance
# ---------------------------------------------------------------------------

run "sam_reserved_concurrency" {
  command = plan

  variables {
    config_path      = "tests/fixtures/sam-reserved-concurrency.yaml"
    config_format    = "sam"
    lambda_code_path = "tests/fixtures"
  }

  assert {
    condition     = aws_lambda_function.functions["InheritFunction"].reserved_concurrent_executions == 5
    error_message = "InheritFunction should inherit Globals.Function.ReservedConcurrentExecutions = 5, got ${jsonencode(aws_lambda_function.functions["InheritFunction"].reserved_concurrent_executions)}"
  }

  assert {
    condition     = aws_lambda_function.functions["OverrideFunction"].reserved_concurrent_executions == 2
    error_message = "OverrideFunction should override Globals with 2, got ${jsonencode(aws_lambda_function.functions["OverrideFunction"].reserved_concurrent_executions)}"
  }

  assert {
    condition     = aws_lambda_function.functions["DisabledFunction"].reserved_concurrent_executions == 0
    error_message = "ReservedConcurrentExecutions: 0 must override the Globals value, not fall back to it, got ${jsonencode(aws_lambda_function.functions["DisabledFunction"].reserved_concurrent_executions)}"
  }
}

# A SAM template that mentions the property nowhere (neither Globals nor
# function) must leave every function unreserved — the brownfield default.
run "sam_no_reservation_stays_null" {
  command = plan

  variables {
    config_path      = "tests/fixtures/sam-globals.yaml"
    config_format    = "sam"
    lambda_code_path = "tests/fixtures"
  }

  assert {
    condition     = alltrue([for f in aws_lambda_function.functions : f.reserved_concurrent_executions == null])
    error_message = "Functions in a template with no ReservedConcurrentExecutions must stay unreserved (null)"
  }
}
