# ============================================================================
# Athena / Glue analytics resources
# ============================================================================
# Maps CloudFormation analytics resources from the resources: section:
#   AWS::Glue::Database      -> aws_glue_catalog_database (Athena databases are
#                               Glue catalog databases)
#   AWS::Athena::WorkGroup   -> aws_athena_workgroup (incl. per-workgroup result
#                               configuration / output location, so a separate
#                               "curated" CTAS workgroup with its own prefix maps
#                               cleanly)
#   AWS::Athena::NamedQuery  -> aws_athena_named_query (named SQL views/queries)

resource "aws_glue_catalog_database" "custom" {
  for_each = local.glue_databases

  # CFN nests the actual database definition under DatabaseInput.
  name = try(
    each.value.Properties.DatabaseInput.Name,
    "${local.to_snake_case[each.key]}_${local.provider_with_defaults.stage}"
  )
  description  = try(each.value.Properties.DatabaseInput.Description, null)
  location_uri = try(each.value.Properties.DatabaseInput.LocationUri, null)
  parameters   = try(each.value.Properties.DatabaseInput.Parameters, null)

  # sls.tf extension (CFN has no tag surface on AWS::Glue::Database): a
  # Properties.Tags MAP, merged over var.global_tags.
  tags = merge(var.global_tags, try({ for k, v in each.value.Properties.Tags : k => tostring(v) }, {}))

  depends_on = [null_resource.config_validation]
}

locals {
  # sls.tf extension: a Glue table may declare `TableInput.ViewSql` (raw SQL)
  # instead of a hand-encoded ViewOriginalText. The module then produces
  # Athena's presto-view envelope itself: "/* Presto View: <base64 json> */"
  # with {originalSql, catalog, schema, columns}, defaults TableType to
  # VIRTUAL_VIEW and injects the presto_view table parameter — so template
  # authors write plain SQL, as they did in pre-migration athena.views blocks.
  _glue_view_sql_tables = {
    for lid, resource in local.glue_tables :
    lid => resource
    if try(resource.Properties.TableInput.ViewSql, null) != null
  }

  # Glue -> Presto column types for the view metadata. Multi-char type names
  # that CONTAIN shorter type names (integer/bigint/smallint/tinyint vs "int")
  # are tokenized first so the bare "int" rewrite can't corrupt them; container
  # syntax maps struct<a:string> -> row(a varchar).
  _glue_view_presto_columns = {
    for lid, resource in local._glue_view_sql_tables :
    lid => [
      for col in try(resource.Properties.TableInput.StorageDescriptor.Columns, []) : {
        name = col.Name
        type = replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(
          lower(tostring(try(col.Type, "string"))),
          "integer", "@i@"),
          "bigint", "@b@"),
          "smallint", "@s@"),
          "tinyint", "@t@"),
          "int", "integer"),
          "@i@", "integer"),
          "@b@", "bigint"),
          "@s@", "smallint"),
          "@t@", "tinyint"),
          "string", "varchar"),
          "float", "real"),
          "binary", "varbinary"),
          "struct<", "row("),
          "array<", "array("),
          "map<", "map("),
          ">", ")"),
        ":", " ")
      }
    ]
  }

  _glue_view_original_text = {
    for lid, resource in local._glue_view_sql_tables :
    lid => "/* Presto View: ${base64encode(jsonencode({
      originalSql = tostring(resource.Properties.TableInput.ViewSql)
      catalog     = "awsdatacatalog"
      schema = try(
        aws_glue_catalog_database.custom[resource.Properties.DatabaseName.Ref].name,
        aws_glue_catalog_database.custom[replace(tostring(resource.Properties.DatabaseName), local._unresolved_ref_prefix, "")].name,
        tostring(resource.Properties.DatabaseName)
      )
      columns = local._glue_view_presto_columns[lid]
    }))} */"
  }
}

# Glue catalog table. Covers both real tables (columns incl. nested struct
# types, storage/serde config, partitions) and Athena VIEWS: an Athena view is
# a Glue table with TableType VIRTUAL_VIEW and the presto-view definition in
# ViewOriginalText ("/* Presto View: <base64 json> */") — the CFN-portable way
# to make e.g. raw_events_flattened directly queryable. Authors can supply
# ViewOriginalText verbatim OR raw SQL via the ViewSql extension (see above).
resource "aws_glue_catalog_table" "custom" {
  for_each = local.glue_tables

  name = try(
    each.value.Properties.TableInput.Name,
    "${local.to_snake_case[each.key]}_${local.provider_with_defaults.stage}"
  )

  # DatabaseName may reference a template AWS::Glue::Database via Ref.
  database_name = try(
    aws_glue_catalog_database.custom[each.value.Properties.DatabaseName.Ref].name,
    aws_glue_catalog_database.custom[replace(tostring(each.value.Properties.DatabaseName), local._unresolved_ref_prefix, "")].name,
    tostring(each.value.Properties.DatabaseName)
  )

  description = try(each.value.Properties.TableInput.Description, null)
  table_type = try(
    each.value.Properties.TableInput.TableType,
    contains(keys(local._glue_view_sql_tables), each.key) ? "VIRTUAL_VIEW" : null
  )

  # ViewSql tables get the presto_view marker parameter Athena requires;
  # explicit Parameters win on conflict.
  parameters = merge(
    contains(keys(local._glue_view_sql_tables), each.key) ? { presto_view = "true", comment = "Presto View" } : {},
    try({ for k, v in each.value.Properties.TableInput.Parameters : k => tostring(v) }, {})
  )

  view_original_text = try(
    each.value.Properties.TableInput.ViewOriginalText,
    local._glue_view_original_text[each.key],
    null
  )
  view_expanded_text = try(
    each.value.Properties.TableInput.ViewExpandedText,
    contains(keys(local._glue_view_sql_tables), each.key) ? "/* Presto View */" : null
  )

  dynamic "storage_descriptor" {
    for_each = try(each.value.Properties.TableInput.StorageDescriptor, null) != null ? [each.value.Properties.TableInput.StorageDescriptor] : []
    content {
      location      = try(storage_descriptor.value.Location, null)
      input_format  = try(storage_descriptor.value.InputFormat, null)
      output_format = try(storage_descriptor.value.OutputFormat, null)
      compressed    = try(storage_descriptor.value.Compressed, false)

      dynamic "columns" {
        for_each = try(storage_descriptor.value.Columns, [])
        content {
          name    = columns.value.Name
          type    = try(columns.value.Type, null)
          comment = try(columns.value.Comment, null)
        }
      }

      dynamic "ser_de_info" {
        for_each = try(storage_descriptor.value.SerdeInfo, null) != null ? [storage_descriptor.value.SerdeInfo] : []
        content {
          name                  = try(ser_de_info.value.Name, null)
          serialization_library = try(ser_de_info.value.SerializationLibrary, null)
          parameters            = try({ for k, v in ser_de_info.value.Parameters : k => tostring(v) }, null)
        }
      }
    }
  }

  dynamic "partition_keys" {
    for_each = try(each.value.Properties.TableInput.PartitionKeys, [])
    content {
      name    = partition_keys.value.Name
      type    = try(partition_keys.value.Type, null)
      comment = try(partition_keys.value.Comment, null)
    }
  }

  depends_on = [null_resource.config_validation]
}

resource "aws_athena_workgroup" "custom" {
  for_each = local.athena_workgroups

  name = try(
    each.value.Properties.Name,
    "${local.to_snake_case[each.key]}-${local.provider_with_defaults.stage}"
  )
  description = try(each.value.Properties.Description, null)
  state       = try(each.value.Properties.State, "ENABLED")

  # CFN RecursiveDeleteOption: delete the workgroup and its contents.
  force_destroy = try(each.value.Properties.RecursiveDeleteOption, false)

  dynamic "configuration" {
    for_each = try(each.value.Properties.WorkGroupConfiguration, null) != null ? [each.value.Properties.WorkGroupConfiguration] : []
    content {
      enforce_workgroup_configuration    = try(configuration.value.EnforceWorkGroupConfiguration, true)
      publish_cloudwatch_metrics_enabled = try(configuration.value.PublishCloudWatchMetricsEnabled, true)
      bytes_scanned_cutoff_per_query     = try(configuration.value.BytesScannedCutoffPerQuery, null)
      requester_pays_enabled             = try(configuration.value.RequesterPaysEnabled, false)

      dynamic "engine_version" {
        for_each = try(configuration.value.EngineVersion, null) != null ? [configuration.value.EngineVersion] : []
        content {
          selected_engine_version = try(engine_version.value.SelectedEngineVersion, "AUTO")
        }
      }

      dynamic "result_configuration" {
        for_each = try(configuration.value.ResultConfiguration, null) != null ? [configuration.value.ResultConfiguration] : []
        content {
          output_location = try(result_configuration.value.OutputLocation, null)

          dynamic "encryption_configuration" {
            for_each = try(result_configuration.value.EncryptionConfiguration, null) != null ? [result_configuration.value.EncryptionConfiguration] : []
            content {
              encryption_option = encryption_configuration.value.EncryptionOption
              kms_key_arn       = try(encryption_configuration.value.KmsKey, null)
            }
          }
        }
      }
    }
  }

  tags = merge(
    var.injected_tags_enabled ? {
      Name        = each.key
      ManagedBy   = "sls.tf"
      LogicalId   = each.key
      Environment = local.provider_with_defaults.stage
    } : {},
    var.global_tags,
    try({
      for tag in each.value.Properties.Tags :
      tag.Key => tag.Value
    }, {})
  )

  depends_on = [null_resource.config_validation]
}

resource "aws_athena_named_query" "custom" {
  for_each = local.athena_named_queries

  name = try(
    each.value.Properties.Name,
    "${local.to_snake_case[each.key]}-${local.provider_with_defaults.stage}"
  )
  description = try(each.value.Properties.Description, null)
  query       = each.value.Properties.QueryString

  # Database may reference a template AWS::Glue::Database via Ref (yaml keeps
  # the {Ref = ...} object; SAM resolves to the database name string).
  database = try(
    aws_glue_catalog_database.custom[each.value.Properties.Database.Ref].name,
    aws_glue_catalog_database.custom[replace(tostring(each.value.Properties.Database), local._unresolved_ref_prefix, "")].name,
    tostring(each.value.Properties.Database)
  )

  # Workgroup may reference a template AWS::Athena::WorkGroup the same way.
  workgroup = try(
    aws_athena_workgroup.custom[each.value.Properties.WorkGroup.Ref].name,
    aws_athena_workgroup.custom[replace(tostring(each.value.Properties.WorkGroup), local._unresolved_ref_prefix, "")].name,
    tostring(each.value.Properties.WorkGroup),
    null
  )

  depends_on = [null_resource.config_validation]
}
