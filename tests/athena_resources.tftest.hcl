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

run "glue_table_properties" {
  command = plan

  variables {
    config_path = "tests/fixtures/athena-analytics.yml"
  }

  assert {
    condition     = length(aws_glue_catalog_table.custom) == 3
    error_message = "Expected 3 Glue tables, got ${length(aws_glue_catalog_table.custom)}"
  }

  # Real table: nested struct column schema survives
  assert {
    condition     = aws_glue_catalog_table.custom["RawEventsTable"].storage_descriptor[0].columns[1].type == "struct<panel:string,zone:int>"
    error_message = "Nested struct column type not translated"
  }

  assert {
    condition     = aws_glue_catalog_table.custom["RawEventsTable"].database_name == "events_db_dev"
    error_message = "Table DatabaseName Ref not resolved to created Glue database"
  }

  assert {
    condition     = aws_glue_catalog_table.custom["RawEventsTable"].storage_descriptor[0].ser_de_info[0].serialization_library == "org.openx.data.jsonserde.JsonSerDe"
    error_message = "SerdeInfo not translated"
  }

  assert {
    condition     = aws_glue_catalog_table.custom["RawEventsTable"].partition_keys[0].name == "dt"
    error_message = "Partition keys not translated"
  }

  # Athena view: VIRTUAL_VIEW + presto-view definition makes it queryable
  assert {
    condition     = aws_glue_catalog_table.custom["FlattenedViewTable"].table_type == "VIRTUAL_VIEW"
    error_message = "View TableType not translated"
  }

  assert {
    condition     = can(regex("Presto View", aws_glue_catalog_table.custom["FlattenedViewTable"].view_original_text))
    error_message = "ViewOriginalText not translated"
  }

  assert {
    condition     = aws_glue_catalog_table.custom["FlattenedViewTable"].parameters["presto_view"] == "true"
    error_message = "presto_view parameter not translated"
  }
}

run "view_sql_encoding" {
  command = plan

  variables {
    config_path = "tests/fixtures/athena-analytics.yml"
  }

  # ViewSql alone implies a view: table_type + presto_view marker defaulted
  assert {
    condition     = aws_glue_catalog_table.custom["SqlViewTable"].table_type == "VIRTUAL_VIEW"
    error_message = "ViewSql table did not default to VIRTUAL_VIEW"
  }

  assert {
    condition     = aws_glue_catalog_table.custom["SqlViewTable"].parameters["presto_view"] == "true"
    error_message = "presto_view parameter not injected for ViewSql table"
  }

  # The generated envelope decodes back to the raw SQL
  assert {
    condition     = jsondecode(base64decode(regex("/\\* Presto View: (\\S+) \\*/", aws_glue_catalog_table.custom["SqlViewTable"].view_original_text)[0])).originalSql == "SELECT sourcedetails.panel AS panel, count(*) AS event_count FROM raw_events GROUP BY 1"
    error_message = "Encoded presto view does not round-trip the raw SQL"
  }

  # Schema points at the resolved database name
  assert {
    condition     = jsondecode(base64decode(regex("/\\* Presto View: (\\S+) \\*/", aws_glue_catalog_table.custom["SqlViewTable"].view_original_text)[0])).schema == "events_db_dev"
    error_message = "Encoded presto view schema incorrect"
  }

  # Glue -> Presto column type mapping: string->varchar, bigint preserved,
  # struct<a:string,b:int> -> row(a varchar,b integer)
  assert {
    condition = jsondecode(base64decode(regex("/\\* Presto View: (\\S+) \\*/", aws_glue_catalog_table.custom["SqlViewTable"].view_original_text)[0])).columns == [
      { name = "panel", type = "varchar" },
      { name = "event_count", type = "bigint" },
      { name = "details", type = "row(panel varchar,zone integer)" },
    ]
    error_message = "Presto column type mapping incorrect: ${jsondecode(base64decode(regex("/\\* Presto View: (\\S+) \\*/", aws_glue_catalog_table.custom["SqlViewTable"].view_original_text)[0])).columns == null ? "null" : jsonencode(jsondecode(base64decode(regex("/\\* Presto View: (\\S+) \\*/", aws_glue_catalog_table.custom["SqlViewTable"].view_original_text)[0])).columns)}"
  }

  # Hand-encoded ViewOriginalText still passes through untouched
  assert {
    condition     = aws_glue_catalog_table.custom["FlattenedViewTable"].view_original_text == "/* Presto View: eyJvcmlnaW5hbFNxbCI6IlNFTEVDVCAxIn0= */"
    error_message = "Explicit ViewOriginalText must pass through verbatim"
  }
}

run "athena_gated_by_resource_types" {
  command = plan

  variables {
    config_path    = "tests/fixtures/athena-analytics.yml"
    resource_types = ["AWS::Glue::Database"]
  }

  # The scoped allowlist + unnamed `ingest` function trips the (intended)
  # naming-convention lint; terraform test surfaces check warnings as failures.
  expect_failures = [check.lambda_naming_convention]

  assert {
    condition     = length(aws_glue_catalog_database.custom) == 1
    error_message = "Allowlisted Glue database should still be created"
  }

  assert {
    condition     = length(aws_athena_workgroup.custom) == 0 && length(aws_athena_named_query.custom) == 0
    error_message = "Non-allowlisted Athena resources should be skipped"
  }
}
