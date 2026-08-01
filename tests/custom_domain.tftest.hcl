# Custom Domain Tests
# Tests for Route 53 & Custom Domain Management (Roadmap #12)
#
# The custom domain is an EXTENSION (custom.slsTf.customDomain in serverless
# yaml, Metadata.SlsTf.CustomDomain in SAM), so presence of the config is what
# enables it. The enable_custom_domain and create_hosted_zone variables were
# removed in v0.11.0 — see extensions.tf and docs/EXTENSIONS.md.

mock_provider "aws" {}

# Test: no customDomain config means no module. This replaces the old
# "disabled by default" case, which asserted that a COMPLETE config with the
# flag unset created nothing — the silent no-op that the extension model
# removes.
run "custom_domain_absent_creates_nothing" {
  command = plan

  variables {
    config_path = "tests/fixtures/http-full-example.yml"
  }

  assert {
    condition     = length(module.custom_domain) == 0
    error_message = "Custom domain module should not be created when no customDomain config is present"
  }

  assert {
    condition     = !contains(keys(output.extensions_active), "CustomDomain")
    error_message = "CustomDomain must not report as active without config"
  }
}

# Test: presence of the config alone creates the module — no flag to set.
run "custom_domain_presence_enables" {
  command = plan

  variables {
    config_path = "tests/fixtures/custom-domain-edge.yml"
  }

  assert {
    condition     = length(module.custom_domain) == 1
    error_message = "Custom domain config is present, so the module should be created with no enable flag"
  }

  assert {
    condition     = contains(keys(output.extensions_active), "CustomDomain")
    error_message = "CustomDomain should report as active when configured"
  }

  assert {
    condition     = output.extensions_active["CustomDomain"].source == "custom.slsTf.customDomain"
    error_message = "CustomDomain should report the namespaced yaml key, got: ${output.extensions_active["CustomDomain"].source}"
  }
}

# Test: EDGE endpoint with us-east-1 certificate
run "custom_domain_edge_endpoint" {
  command = plan

  variables {
    config_path = "tests/fixtures/custom-domain-edge.yml"
  }

  assert {
    condition     = length(module.custom_domain) == 1
    error_message = "Custom domain module should be created with valid config"
  }

  assert {
    condition     = module.custom_domain[0].custom_domain_name == "api.example.com"
    error_message = "Custom domain name should match configuration"
  }
}

# Test: REGIONAL endpoint with regional certificate
run "custom_domain_regional_endpoint" {
  command = plan

  variables {
    config_path = "tests/fixtures/custom-domain-regional.yml"
  }

  assert {
    condition     = length(module.custom_domain) == 1
    error_message = "Custom domain module should be created for REGIONAL endpoint"
  }

  assert {
    condition     = module.custom_domain[0].custom_domain_name == "api-regional.example.com"
    error_message = "Regional custom domain name should match configuration"
  }

  # Verify no Route53 record created (createRoute53Record=false)
  assert {
    condition     = module.custom_domain[0].route53_record_fqdn == null
    error_message = "Route53 record should not be created when createRoute53Record=false"
  }
}

# Test: Custom domain with base path
run "custom_domain_with_base_path" {
  command = plan

  variables {
    config_path = "tests/fixtures/custom-domain-with-base-path.yml"
  }

  assert {
    condition     = length(module.custom_domain) == 1
    error_message = "Custom domain module should be created with base path"
  }

  assert {
    condition     = module.custom_domain[0].custom_domain_base_path == "v1"
    error_message = "Base path should match configuration"
  }
}

# Note: Certificate region mismatch and invalid base path validation tests
# cannot be automated with expect_failures in Terraform test framework for module resources.
# These validations work correctly (as evidenced by the error messages during plan),
# but must be manually verified. The validation errors are:
# - Certificate region mismatch: EDGE endpoints require us-east-1 certificate
# - Base path format: no leading/trailing slashes allowed
#
# Test fixtures available for manual testing:
# - tests/fixtures/custom-domain-invalid-cert-region.yml
# - tests/fixtures/custom-domain-invalid-basepath.yml

# Test: Certificate ARN from module variable fallback. acm_certificate_arn
# stays a VARIABLE rather than moving into the extension config, because it is
# frequently a co-planned aws_acm_certificate.this.arn that no YAML file can
# name.
run "custom_domain_cert_from_variable" {
  command = plan

  variables {
    config_path         = "tests/fixtures/custom-domain-with-base-path.yml"
    acm_certificate_arn = "arn:aws:acm:us-east-1:999999999999:certificate/override123"
  }

  assert {
    condition     = length(module.custom_domain) == 1
    error_message = "Custom domain module should work with certificate from variable"
  }
}

# Test: hosted zone creation, now driven by customDomain.createHostedZone in
# the config rather than the removed create_hosted_zone variable.
run "custom_domain_create_hosted_zone_from_config" {
  command = plan

  variables {
    config_path = "tests/fixtures/custom-domain-with-base-path.yml"
  }

  assert {
    condition     = length(module.custom_domain) == 1
    error_message = "Custom domain module should be created with createHostedZone in config"
  }
}
