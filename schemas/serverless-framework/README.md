# Serverless Framework JSON Schemas

This directory contains vendored JSON schemas for Serverless Framework versions 2.x, 3.x, and 4.x.

## Schema Files

| File | Version | Draft | Source | Date Vendored |
|------|---------|-------|--------|---------------|
| `v2.x.json` | 2.x | Draft-04 | https://github.com/softprops/serverless-yml-schema | 2025-10-28 |
| `v3.x.json` | 3.x | Draft-07 | Extended from community schema + official docs | 2025-10-28 |
| `v4.x.json` | 4.x | Draft-07 | Extended from v3.x + v4 release notes | 2025-10-28 |

## Schema Sources

### v2.x Schema
Based on the community-maintained schema from https://github.com/softprops/serverless-yml-schema, which provides comprehensive validation for Serverless Framework v2.x configurations.

### v3.x Schema
Extended from the v2.x schema with updates for:
- Service name as object format support
- Updated runtime options (Node.js 18.x, Python 3.11, Java 17, etc.)
- Package patterns (replacing include/exclude)
- Architecture support (x86_64, arm64)
- Enhanced IAM configuration
- Extended memory limits (up to 10240 MB)
- Updated API Gateway endpoint types
- Draft-07 schema format

### v4.x Schema
Extended from v3.x with v4-specific features:
- Lambda function URLs
- Latest runtimes (Node.js 20.x, Python 3.12, Ruby 3.3, Java 21, .NET 8)
- provided.al2023 runtime
- HTTP API (API Gateway v2) configuration
- Enhanced deployment bucket configuration
- X-Ray tracing configuration
- CloudFormation resource extensions
- useDotenv flag
- Expanded logRetentionInDays options

## Version Detection

The schema generator uses the `frameworkVersion` field in serverless.yml to determine which schema to apply:

```yaml
frameworkVersion: '3'  # Uses v3.x.json
frameworkVersion: '>=3.0.0 <4.0.0'  # Uses v3.x.json
frameworkVersion: '4'  # Uses v4.x.json
```

If `frameworkVersion` is not specified, v3.x is assumed as the default.

## Updating Schemas

Schemas should be updated when:
1. New Serverless Framework versions are released with breaking changes
2. New properties or constraints are added to the configuration format
3. Runtime versions are added or deprecated

### Manual Update Process

1. Check Serverless Framework releases: https://github.com/serverless/serverless/releases
2. Review change logs for configuration schema changes
3. Update the appropriate JSON schema file(s)
4. Update the "Date Vendored" in this README
5. Run the schema generator to regenerate validation code:
   ```bash
   npm run generate:validation:all
   ```
6. Test generated validation against sample configurations
7. Commit both schema and generated validation files

### Automated Update Process

The CI/CD workflow `.github/workflows/schema-update.yml` runs weekly to:
1. Fetch latest Serverless Framework releases
2. Download current schemas from upstream sources
3. Compare SHA-256 hashes with vendored schemas
4. Create pull requests when differences are detected

## Schema Validation

All schemas are validated against their respective JSON Schema draft specifications:
- v2.x: JSON Schema Draft-04
- v3.x: JSON Schema Draft-07
- v4.x: JSON Schema Draft-07

Run schema validation tests:
```bash
cd tools/schema-generator
npm test
```

## References

- [Serverless Framework Documentation](https://www.serverless.com/framework/docs/)
- [Serverless Framework GitHub](https://github.com/serverless/serverless)
- [Community JSON Schema](https://github.com/softprops/serverless-yml-schema)
- [JSON Schema Specification](https://json-schema.org/specification.html)
- [AWS Lambda Runtimes](https://docs.aws.amazon.com/lambda/latest/dg/lambda-runtimes.html)

## Schema Coverage

The schemas in this directory cover the most commonly used properties in Serverless Framework configurations. The schema generator uses a configuration file (`tools/schema-generator/config.yml`) to control which schema paths are validated, allowing for incremental coverage as features are implemented in the sls.tf module.

### Currently Included Paths
- `/properties/service` - Service identifier
- `/properties/provider` - Cloud provider configuration
- `/properties/functions` - Lambda function definitions

### Currently Excluded Paths
- `/properties/plugins` - Plugin configuration (too variable)
- `/properties/package` - Packaging options (not yet implemented in module)

See `tools/schema-generator/config.yml` for the complete list of included/excluded paths.
