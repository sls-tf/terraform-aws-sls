# ============================================================================
# TypeScript Configuration Parser (Roadmap #6)
# ============================================================================
#
# This file implements TypeScript configuration file parsing using external data sources.
# It supports serverless.ts files with async exports, complex TypeScript features,
# and comprehensive error handling.
#
# Features:
# - Parse serverless.ts configuration files
# - Handle async function exports and Promise returns
# - Support for TypeScript modules and imports
# - Comprehensive error handling and validation
# - Integration with existing validation pipeline

# External data source for TypeScript configuration parsing
# This executes a Node.js script that runs serverless.ts via Node's native
# TypeScript support (or a custom SLS_TF_TS_RUNNER) and returns JSON
# It supports both local NPM installation and module script paths
data "external" "typescript_config" {
  count = var.config_format == "typescript" ? 1 : 0

  # Try to find the parser script in local node_modules first, then fall back to module path
  program = [
    "node",
    fileexists("${path.cwd}/node_modules/sls-tf/scripts/typescript-parser.js")
    ? "${path.cwd}/node_modules/sls-tf/scripts/typescript-parser.js"
    : "${path.module}/scripts/typescript-parser.js"
  ]

  query = {
    config_path       = var.config_path
    working_directory = path.cwd
    using_local_npm   = fileexists("${path.cwd}/node_modules/sls-tf/scripts/typescript-parser.js")
  }
}

# Parse the TypeScript configuration from external data source result
locals {
  # TypeScript configuration parsing (only when config_format is "typescript")
  typescript_config_raw = var.config_format == "typescript" ? (
    try(jsondecode(try(data.external.typescript_config[0].result.config, "")), null)
  ) : null

  # Extract error message if TypeScript parsing failed
  typescript_parse_error = var.config_format == "typescript" ? (
    try(data.external.typescript_config[0].result.error, null)
  ) : null

  # Check that the parser scripts ship with the module. No `npm install` is
  # required for the TypeScript path: it runs on Node's native TypeScript support
  # (Node >= 22.7), or a custom runner set via SLS_TF_TS_RUNNER (e.g. "npx tsx").
  # Node-version / engine problems are reported at runtime by the parser itself
  # (surfaced via typescript_parse_error) with actionable messages.
  typescript_dependencies_check = var.config_format == "typescript" ? (
    (fileexists("${path.cwd}/node_modules/sls-tf/scripts/typescript-parser.js") &&
    fileexists("${path.cwd}/node_modules/sls-tf/scripts/ts-config-loader.mjs")) ||
    (fileexists("${path.module}/scripts/typescript-parser.js") &&
    fileexists("${path.module}/scripts/ts-config-loader.mjs"))
  ) : true

  # Enhanced file content handling for TypeScript
  file_content_typescript = var.config_format == "typescript" ? (
    local.typescript_config_raw != null ? jsonencode(local.typescript_config_raw) : null
  ) : local.file_content

  # Error collection for TypeScript parsing
  typescript_errors = var.config_format == "typescript" ? concat(
    local.typescript_parse_error != null ? ["TypeScript parsing failed: ${local.typescript_parse_error}"] : [],
    !local.typescript_dependencies_check ? ["TypeScript parser scripts not found in the module installation (scripts/typescript-parser.js + ts-config-loader.mjs)."] : [],
    local.typescript_config_raw == null && local.typescript_parse_error == null ? ["Unknown TypeScript parsing error occurred."] : []
  ) : []

  # TypeScript configuration validation
  typescript_validation_errors = var.config_format == "typescript" && local.typescript_config_raw != null ? (
    local.typescript_config_raw.service == null ? ["Missing required field 'service' in TypeScript configuration."] : []
  ) : []

  # Combined TypeScript parsing and validation errors
  typescript_all_errors = var.config_format == "typescript" ? concat(
    local.typescript_errors,
    local.typescript_validation_errors
  ) : []

  # Fatal error indicator for TypeScript parsing
  typescript_has_fatal_error = var.config_format == "typescript" && length(local.typescript_all_errors) > 0

  # Success indicator for TypeScript parsing
  typescript_parse_success = var.config_format == "typescript" && (
    local.typescript_config_raw != null && length(local.typescript_all_errors) == 0
  )

  # Final parsed configuration with TypeScript support
  parsed_config_with_typescript = var.config_format == "typescript" ? (
    local.typescript_parse_success ? local.typescript_config_raw : null
  ) : (var.config_format == "yaml" && local.file_content != null ? try(yamldecode(local.file_content), null) : null)
}