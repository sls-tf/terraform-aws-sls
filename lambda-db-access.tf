# ============================================================================
# dbAccess shorthand — read/write grants over the template's DynamoDB tables
# ============================================================================
# Platform modules commonly grant every lambda blanket table access
# (`db_access: read` by default) instead of hand-written statements. This maps
# that shape: a function-level `dbAccess: read | write` (yaml) or
# `DbAccess: read | write` (SAM extension property) grants the corresponding
# action set over ALL DynamoDB tables created from the resources: section
# (tables + their indexes) on the module-created role. Functions without the
# key get nothing — access stays explicit unless asked for.

locals {
  _db_access_actions = {
    read = [
      "dynamodb:GetItem",
      "dynamodb:BatchGetItem",
      "dynamodb:Query",
      "dynamodb:Scan",
      "dynamodb:DescribeTable",
    ]
    write = [
      "dynamodb:GetItem",
      "dynamodb:BatchGetItem",
      "dynamodb:Query",
      "dynamodb:Scan",
      "dynamodb:DescribeTable",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
      "dynamodb:BatchWriteItem",
    ]
  }

  _function_db_access = {
    for fn in local._function_names :
    fn => lower(tostring(var.config_format == "sam" ? (
      try(local.sam_structure.Resources[fn].Properties.DbAccess, "")
      ) : (
      try(local.parsed_config.functions[fn].dbAccess, try(local.parsed_config.functions[fn].db_access, ""))
    )))
  }
}

resource "aws_iam_role_policy" "lambda_db_access" {
  for_each = {
    for fn, access in local._function_db_access :
    fn => access
    if contains(["read", "write"], access) && !try(local._function_has_explicit_role[fn], false)
  }

  name = "db-access-${each.value}"
  role = aws_iam_role.lambda_execution[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = local._db_access_actions[each.value]
      Resource = flatten([
        for lid in keys(local.dynamodb_tables) : [
          aws_dynamodb_table.custom[lid].arn,
          "${aws_dynamodb_table.custom[lid].arn}/index/*",
        ]
      ])
    }]
  })
}
