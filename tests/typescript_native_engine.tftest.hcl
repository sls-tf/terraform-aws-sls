# TypeScript Native-Engine Tests
#
# The serverless.ts path runs on Node's built-in TypeScript support
# (--experimental-transform-types, Node >= 22.7) by default, with NO ts-node,
# NO typescript package, and NO npm install — only `node` on PATH. ts-node is an
# optional compatibility engine, auto-used when installed, for legacy configs.
#
# This test exercises the default (native, zero-install) engine end to end, the
# CI-realistic path where scripts/node_modules has no ts-node. It uses a mock AWS
# provider so it needs no LocalStack or AWS credentials, but it does require the
# host Node to be >= 22.7 (older Node fails loud with an upgrade message instead).

mock_provider "aws" {}

run "native_engine_parses_serverless_ts" {
  command = plan

  variables {
    config_path   = "tests/fixtures/valid-minimal.ts"
    config_format = "typescript"
  }

  assert {
    condition     = local.parsed_config.service == "my-typescript-service"
    error_message = "Native TypeScript engine should parse serverless.ts with no ts-node/npm install"
  }

  assert {
    condition     = local.parsed_config.provider.name == "aws"
    error_message = "Parsed serverless.ts provider should resolve"
  }
}
