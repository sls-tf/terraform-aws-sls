# structural_sam_parameters: a param used in resource names + referenced by an
# event must resolve to the SAME name in the structural parse (event wiring) as
# in the resolved parse (the resource), when the caller value differs from the
# template Default.

mock_provider "aws" {}

override_data {
  target = data.aws_region.current
  values = {
    region = "eu-west-2"
    name   = "eu-west-2"
  }
}

override_data {
  target = data.aws_caller_identity.current
  values = {
    account_id = "534294601285"
  }
}

# With Enviroment declared structural, the S3 notification keys off the RESOLVED
# bucket name (vids-prod), matching the created bucket.
run "structural_param_aligns_event_wiring" {
  command = plan

  variables {
    config_path               = "tests/fixtures/sam-structural-params.yaml"
    config_format             = "sam"
    sam_template_parameters   = { Enviroment = "prod" }
    structural_sam_parameters = ["Enviroment"]
  }

  assert {
    condition     = contains(keys(aws_s3_bucket.custom), "VideosBucket")
    error_message = "bucket should be created"
  }
  assert {
    condition     = aws_s3_bucket.custom["VideosBucket"].bucket == "vids-prod"
    error_message = "bucket name must resolve to vids-prod"
  }
  assert {
    condition     = contains(keys(aws_s3_bucket_notification.lambda_triggers), "vids-prod")
    error_message = "S3 notification must target vids-prod (structural param resolved), not the Default vids-dev"
  }
}

# Backward-compat: WITHOUT declaring it structural, the notification keys off the
# Default-resolved name (vids-dev) — the pre-fix behaviour, unchanged.
run "default_behaviour_unchanged" {
  command = plan

  variables {
    config_path             = "tests/fixtures/sam-structural-params.yaml"
    config_format           = "sam"
    sam_template_parameters = { Enviroment = "prod" }
  }

  assert {
    condition     = contains(keys(aws_s3_bucket_notification.lambda_triggers), "vids-dev")
    error_message = "Without structural_sam_parameters the structural parse still uses the Default (vids-dev)."
  }
}
