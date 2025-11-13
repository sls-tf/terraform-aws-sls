## Schema Update

This is an automated pull request updating the vendored Serverless Framework schemas and regenerating validation code.

### Schema Versions Updated

| Version | Previous | New | Status |
|---------|----------|-----|--------|
| v2.x | <!-- previous-v2 --> | <!-- new-v2 --> | <!-- status-v2 --> |
| v3.x | <!-- previous-v3 --> | <!-- new-v3 --> | <!-- status-v3 --> |
| v4.x | <!-- previous-v4 --> | <!-- new-v4 --> | <!-- status-v4 --> |

### Validation Rules Changed

<!-- This section will be filled automatically with diff stats -->

**Generated Files Modified:**
- `generated/validation-v2.tf`
- `generated/validation-v3.tf`
- `generated/validation-v4.tf`

### Review Checklist

Please verify the following before merging:

#### Automated Checks
- [ ] All GitHub Actions workflows pass
- [ ] Generated code validation passes (`validate-generated-code.yml`)
- [ ] Terraform fmt check passes
- [ ] Schema generator tests pass (49 tests expected)

#### Manual Review
- [ ] **Schema Changes:** Review the diff in `schemas/serverless-framework/` for any significant changes
- [ ] **Validation Rules:** Check `generated/validation-*.tf` for new or modified validation rules
- [ ] **Breaking Changes:** Verify that schema changes don't introduce breaking changes for existing users
  - New required fields (would break existing configs)
  - Removed enum values (would invalidate existing configs)
  - Changed type constraints (could reject previously valid configs)
- [ ] **Error Messages:** Ensure new validation error messages are clear and helpful
- [ ] **Documentation:** Determine if any documentation updates are needed

#### Testing Recommendations
- [ ] Test with sample `serverless.yml` files for each version (v2, v3, v4)
- [ ] Verify validation correctly rejects invalid configurations
- [ ] Verify validation accepts valid configurations
- [ ] Check error messages are actionable

### Impact Assessment

**Risk Level:** <!-- LOW / MEDIUM / HIGH -->

**Reasoning:**
<!-- Explain why this update is low/medium/high risk -->
<!-- Consider: scope of changes, breaking changes, affected validation rules -->

### Notes

- **Auto-generated:** This PR was created by the `schema-update.yml` workflow
- **Generator Version:** schema-generator v0.1.0
- **Schemas Source:** [serverless/serverless](https://github.com/serverless/serverless) repository
- **Regeneration Command:** `npm run generate:validation`

### Related Issues

<!-- Link any related issues, feature requests, or bug reports -->

---

**For Reviewers:**

If you need to make changes:
1. DO NOT edit files in `generated/` directory directly
2. Make changes to templates in `tools/schema-generator/templates/` instead
3. Update configuration in `tools/schema-generator/config.yml` if needed
4. Regenerate with `npm run generate:validation`
5. Commit the regenerated files

For questions about the schema generator, see:
- [Schema Generator README](../../tools/schema-generator/README.md)
- [Maintenance Documentation](../../tools/schema-generator/MAINTENANCE.md)
- [Contributing Guide](../../docs/CONTRIBUTING-GENERATED-CODE.md)
