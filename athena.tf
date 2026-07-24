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
    {
      Name        = each.key
      ManagedBy   = "sls.tf"
      LogicalId   = each.key
      Environment = local.provider_with_defaults.stage
    },
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
