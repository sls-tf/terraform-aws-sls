# Custom Domain Tests
# Tests for Route 53 & Custom Domain Management (Roadmap #12)

# Test: Custom domain module not created when disabled
mock_provider "aws" {}

run "custom_domain_disabled_by_default" {
  command = plan

  variables {
    config_path = "tests/fixtures/http-full-example.yml"
    # enable_custom_domain defaults to false
  }

  assert {
    condition     = length(module.custom_domain) == 0
    error_message = "Custom domain module should not be created when enable_custom_domain=false"
  }
}

# Test: Custom domain module not created when no customDomain block
run "custom_domain_no_config" {
  command = plan

  variables {
    config_path          = "tests/fixtures/http-full-example.yml"
    enable_custom_domain = true
  }

  assert {
    condition     = length(module.custom_domain) == 0
    error_message = "Custom domain module should not be created when customDomain block missing"
  }
}

# Test: EDGE endpoint with us-east-1 certificate
run "custom_domain_edge_endpoint" {
  command = plan

  variables {
    config_path          = "tests/fixtures/custom-domain-edge.yml"
    enable_custom_domain = true
    create_hosted_zone   = true
  }

  # Verify module created
  assert {
    condition     = length(module.custom_domain) == 1
    error_message = "Custom domain module should be created with valid config"
  }

  # Verify domain name output
  assert {
    condition     = module.custom_domain[0].custom_domain_name == "api.example.com"
    error_message = "Custom domain name should match configuration"
  }
}

# Test: REGIONAL endpoint with regional certificate
run "custom_domain_regional_endpoint" {
  command = plan

  variables {
    config_path          = "tests/fixtures/custom-domain-regional.yml"
    enable_custom_domain = true
    create_hosted_zone   = true
  }

  # Verify module created
  assert {
    condition     = length(module.custom_domain) == 1
    error_message = "Custom domain module should be created for REGIONAL endpoint"
  }

  # Verify domain name
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
    config_path          = "tests/fixtures/custom-domain-with-base-path.yml"
    enable_custom_domain = true
    create_hosted_zone   = true
  }

  # Verify module created
  assert {
    condition     = length(module.custom_domain) == 1
    error_message = "Custom domain module should be created with base path"
  }

  # Verify base path
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

# Test: Certificate ARN from module variable fallback
run "custom_domain_cert_from_variable" {
  command = plan

  variables {
    config_path          = "tests/fixtures/custom-domain-with-base-path.yml"
    enable_custom_domain = true
    create_hosted_zone   = true
    # Override certificate via module variable (though fixture also has one)
    acm_certificate_arn = "arn:aws:acm:us-east-1:999999999999:certificate/override123"
  }

  # Module should still be created
  assert {
    condition     = length(module.custom_domain) == 1
    error_message = "Custom domain module should work with certificate from variable"
  }
}

# Test: Hosted zone creation when create_hosted_zone=true
run "custom_domain_create_hosted_zone" {
  command = plan

  variables {
    config_path          = "tests/fixtures/custom-domain-with-base-path.yml"
    enable_custom_domain = true
    create_hosted_zone   = true
  }

  # Verify module created
  assert {
    condition     = length(module.custom_domain) == 1
    error_message = "Custom domain module should be created with create_hosted_zone=true"
  }
}
