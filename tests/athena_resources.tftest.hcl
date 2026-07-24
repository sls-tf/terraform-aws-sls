# Test: Athena / Glue analytics resource translation
# Validates AWS::Glue::Database, AWS::Athena::WorkGroup and AWS::Athena::NamedQuery
# translation to aws_glue_catalog_database / aws_athena_workgroup / aws_athena_named_query

mock_provider "aws" {}

run "athena_resources_created" {
  command = plan

  variables {
    config_path = "tests/fixtures/athena-analytics.yml"
  }

  assert {
    condition     = length(aws_glue_catalog_database.custom) == 1
    error_message = "Expected 1 Glue database, got ${length(aws_glue_catalog_database.custom)}"
  }

  assert {
    condition     = length(aws_athena_workgroup.custom) == 2
    error_message = "Expected 2 Athena workgroups, got ${length(aws_athena_workgroup.custom)}"
  }

  assert {
    condition     = length(aws_athena_named_query.custom) == 1
    error_message = "Expected 1 Athena named query, got ${length(aws_athena_named_query.custom)}"
  }
}

run "glue_database_properties" {
  command = plan

  variables {
    config_path = "tests/fixtures/athena-analytics.yml"
  }

  assert {
    condition     = aws_glue_catalog_database.custom["EventsDatabase"].name == "events_db_dev"
    error_message = "Glue database name not translated from DatabaseInput.Name"
  }

  assert {
    condition     = aws_glue_catalog_database.custom["EventsDatabase"].description == "Raw event data"
    error_message = "Glue database description not translated"
  }
}

run "athena_workgroup_properties" {
  command = plan

  variables {
    config_path = "tests/fixtures/athena-analytics.yml"
  }

  assert {
    condition     = aws_athena_workgroup.custom["RawWorkGroup"].name == "raw-events-dev"
    error_message = "RawWorkGroup name not translated"
  }

  assert {
    condition     = aws_athena_workgroup.custom["RawWorkGroup"].configuration[0].enforce_workgroup_configuration == true
    error_message = "RawWorkGroup enforce_workgroup_configuration not translated"
  }

  assert {
    condition     = aws_athena_workgroup.custom["RawWorkGroup"].configuration[0].result_configuration[0].output_location == "s3://query-results-bucket/raw/"
    error_message = "RawWorkGroup output_location not translated"
  }

  # Curated workgroup has its own lifecycle/prefix config
  assert {
    condition     = aws_athena_workgroup.custom["CuratedWorkGroup"].force_destroy == true
    error_message = "CuratedWorkGroup RecursiveDeleteOption not mapped to force_destroy"
  }

  assert {
    condition     = aws_athena_workgroup.custom["CuratedWorkGroup"].configuration[0].bytes_scanned_cutoff_per_query == 10737418240
    error_message = "CuratedWorkGroup BytesScannedCutoffPerQuery not translated"
  }

  assert {
    condition     = aws_athena_workgroup.custom["CuratedWorkGroup"].configuration[0].result_configuration[0].output_location == "s3://query-results-bucket/curated/"
    error_message = "CuratedWorkGroup output_location not translated"
  }

  assert {
    condition     = aws_athena_workgroup.custom["CuratedWorkGroup"].configuration[0].result_configuration[0].encryption_configuration[0].encryption_option == "SSE_S3"
    error_message = "CuratedWorkGroup encryption option not translated"
  }
}

run "athena_named_query_properties" {
  command = plan

  variables {
    config_path = "tests/fixtures/athena-analytics.yml"
  }

  assert {
    condition     = aws_athena_named_query.custom["RawEventsFlattenedView"].name == "raw_events_flattened"
    error_message = "Named query name not translated"
  }

  # Ref: EventsDatabase resolves to the created Glue database name
  assert {
    condition     = aws_athena_named_query.custom["RawEventsFlattenedView"].database == "events_db_dev"
    error_message = "Named query Database Ref not resolved to created Glue database"
  }

  # Ref: RawWorkGroup resolves to the created workgroup name
  assert {
    condition     = aws_athena_named_query.custom["RawEventsFlattenedView"].workgroup == "raw-events-dev"
    error_message = "Named query WorkGroup Ref not resolved to created workgroup"
  }

  assert {
    condition     = can(regex("CREATE OR REPLACE VIEW", aws_athena_named_query.custom["RawEventsFlattenedView"].query))
    error_message = "Named query QueryString not translated"
  }
}

run "athena_gated_by_resource_types" {
  command = plan

  variables {
    config_path    = "tests/fixtures/athena-analytics.yml"
    resource_types = ["AWS::Glue::Database"]
  }

  assert {
    condition     = length(aws_glue_catalog_database.custom) == 1
    error_message = "Allowlisted Glue database should still be created"
  }

  assert {
    condition     = length(aws_athena_workgroup.custom) == 0 && length(aws_athena_named_query.custom) == 0
    error_message = "Non-allowlisted Athena resources should be skipped"
  }
}
