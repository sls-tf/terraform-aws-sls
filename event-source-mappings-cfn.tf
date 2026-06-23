# ============================================================================
# Standalone AWS::Lambda::EventSourceMapping resources
# ============================================================================
# SAM/CloudFormation templates sometimes wire a DynamoDB stream (or Kinesis/SQS)
# to a function with an explicit AWS::Lambda::EventSourceMapping resource rather
# than a function `Events:` entry. This file creates aws_lambda_event_source_mapping
# for those.
#
# Reference resolution (all from the resolved parse, which fabricates
# deterministic ARNs for !GetAtt):
#   FunctionName    — !GetAtt Fn.Arn / !Ref Fn / name → function logical ID →
#                     aws_lambda_function.functions[<id>].
#   EventSourceArn  — for a template DynamoDB table's !GetAtt Table.StreamArn the
#                     preprocessor yields a wildcard ".../stream/*" placeholder, so
#                     we map the table name back to the created table and use its
#                     real stream_arn. Non-table sources (SQS/Kinesis ARNs) pass
#                     through as resolved.

locals {
  sam_event_source_mappings = {
    for logical_id, resource in local._custom_resources_structure :
    logical_id => resource
    if try(resource.Type, "") == "AWS::Lambda::EventSourceMapping"
    && (var.resource_types == null || contains(var.resource_types, "AWS::Lambda::EventSourceMapping"))
  }

  # Created DynamoDB table name -> logical ID (to recover real stream ARNs).
  _table_name_to_logical = {
    for logical_id in keys(local.dynamodb_tables) :
    tostring(try(local._custom_resources_structure[logical_id].Properties.TableName, logical_id)) => logical_id
  }

  cfn_esm_config = {
    for logical_id, resource in local.sam_event_source_mappings :
    logical_id => {
      # Function: prefer the :function:<name> segment of a resolved ARN, else a
      # stripped !Ref marker; map either to a function logical ID.
      function_id = try(
        local._function_name_to_logical[regex("function:([^/]+)", tostring(try(local.custom_resources_raw[logical_id].Properties.FunctionName, "")))[0]],
        try(local._function_name_to_logical[replace(tostring(try(local.custom_resources_raw[logical_id].Properties.FunctionName, "")), local._unresolved_ref_prefix, "")], "")
      )

      # Source table logical ID, recovered from a "table/<name>/stream..." ARN.
      source_table_id = try(
        local._table_name_to_logical[regex("table/([^/]+)/", tostring(try(local.custom_resources_raw[logical_id].Properties.EventSourceArn, "")))[0]],
        ""
      )

      event_source_arn_raw = tostring(try(local.custom_resources_raw[logical_id].Properties.EventSourceArn, ""))
      batch_size           = try(local.custom_resources_raw[logical_id].Properties.BatchSize, null)
      enabled              = try(local.custom_resources_raw[logical_id].Properties.Enabled, true)
      starting_position    = try(tostring(local.custom_resources_raw[logical_id].Properties.StartingPosition), null)
    }
  }
}

resource "aws_lambda_event_source_mapping" "cfn" {
  for_each = local.sam_event_source_mappings

  function_name = aws_lambda_function.functions[local.cfn_esm_config[each.key].function_id].arn

  # Use the created table's real stream ARN when the source maps to a template
  # table; otherwise the resolved ARN (SQS/Kinesis/external).
  event_source_arn = local.cfn_esm_config[each.key].source_table_id != "" ? aws_dynamodb_table.custom[local.cfn_esm_config[each.key].source_table_id].stream_arn : local.cfn_esm_config[each.key].event_source_arn_raw

  batch_size        = local.cfn_esm_config[each.key].batch_size
  enabled           = local.cfn_esm_config[each.key].enabled
  starting_position = local.cfn_esm_config[each.key].starting_position

  depends_on = [null_resource.config_validation]
}
