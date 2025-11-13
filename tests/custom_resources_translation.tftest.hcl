# Custom Resource Translation Tests
# Tests for CloudFormation to Terraform resource translation (Roadmap #9)

# Test: S3 bucket translation
run "s3_bucket_translation" {
  command = plan

  variables {
    config_path = "tests/fixtures/custom-resources-s3-basic.yml"
  }

  # Verify S3 buckets created
  assert {
    condition     = length(aws_s3_bucket.custom) == 2
    error_message = "Should create 2 S3 buckets from CloudFormation resources"
  }

  # Verify bucket naming (use contains for plan-time checks)
  assert {
    condition     = contains(keys(aws_s3_bucket.custom), "UploadBucket")
    error_message = "Should create bucket with UploadBucket logical ID"
  }

  assert {
    condition     = contains(keys(aws_s3_bucket.custom), "DataBucket")
    error_message = "Should create bucket with DataBucket logical ID"
  }

  # Verify versioning configuration created for DataBucket
  assert {
    condition     = length(aws_s3_bucket_versioning.custom) == 1
    error_message = "Should create versioning config for DataBucket"
  }

  # Verify ACL configuration created for DataBucket
  assert {
    condition     = length(aws_s3_bucket_acl.custom) == 1
    error_message = "Should create ACL config for DataBucket"
  }

  # Verify outputs
  assert {
    condition     = length(output.custom_s3_bucket_ids) == 2
    error_message = "Should output 2 bucket IDs"
  }
}

# Test: DynamoDB table translation
run "dynamodb_table_translation" {
  command = plan

  variables {
    config_path = "tests/fixtures/custom-resources-dynamodb.yml"
  }

  # Verify DynamoDB table created
  assert {
    condition     = length(aws_dynamodb_table.custom) == 1
    error_message = "Should create 1 DynamoDB table from CloudFormation resources"
  }

  # Verify table logical ID
  assert {
    condition     = contains(keys(aws_dynamodb_table.custom), "UsersTable")
    error_message = "Should create table with UsersTable logical ID"
  }

  # Verify billing mode
  assert {
    condition     = aws_dynamodb_table.custom["UsersTable"].billing_mode == "PAY_PER_REQUEST"
    error_message = "Should use PAY_PER_REQUEST billing mode"
  }

  # Verify hash key
  assert {
    condition     = aws_dynamodb_table.custom["UsersTable"].hash_key == "userId"
    error_message = "Should set userId as hash key"
  }

  # Verify attributes defined
  assert {
    condition     = length(aws_dynamodb_table.custom["UsersTable"].attribute) == 2
    error_message = "Should define 2 attributes (userId and email)"
  }

  # Verify outputs
  assert {
    condition     = length(output.custom_dynamodb_table_names) == 1
    error_message = "Should output 1 table name"
  }
}

# Test: Mixed resource types
run "mixed_resources_translation" {
  command = plan

  variables {
    config_path = "tests/fixtures/custom-resources-mixed.yml"
  }

  # Verify all resource types created
  assert {
    condition     = length(aws_s3_bucket.custom) == 1
    error_message = "Should create 1 S3 bucket"
  }

  assert {
    condition     = length(aws_dynamodb_table.custom) == 1
    error_message = "Should create 1 DynamoDB table"
  }

  # Verify resource counts in outputs
  assert {
    condition     = output.custom_resources_count.s3_buckets == 1
    error_message = "Should output count of 1 S3 bucket"
  }

  assert {
    condition     = output.custom_resources_count.dynamodb_tables == 1
    error_message = "Should output count of 1 DynamoDB table"
  }

  # Verify DynamoDB table with PROVISIONED billing mode
  assert {
    condition     = aws_dynamodb_table.custom["MyTable"].billing_mode == "PROVISIONED"
    error_message = "MyTable should use PROVISIONED billing mode"
  }

  # Verify read/write capacity set for PROVISIONED mode
  assert {
    condition     = aws_dynamodb_table.custom["MyTable"].read_capacity == 5
    error_message = "MyTable should have read_capacity of 5"
  }

  assert {
    condition     = aws_dynamodb_table.custom["MyTable"].write_capacity == 5
    error_message = "MyTable should have write_capacity of 5"
  }
}

# Test: Resource naming convention
run "resource_naming_convention" {
  command = plan

  variables {
    config_path = "tests/fixtures/custom-resources-s3-basic.yml"
  }

  # Verify tags include logical ID
  assert {
    condition     = aws_s3_bucket.custom["UploadBucket"].tags["LogicalId"] == "UploadBucket"
    error_message = "Bucket should be tagged with original logical ID"
  }

  assert {
    condition     = aws_s3_bucket.custom["UploadBucket"].tags["ManagedBy"] == "sls.tf"
    error_message = "Bucket should be tagged with ManagedBy=sls.tf"
  }
}
