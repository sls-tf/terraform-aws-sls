# ============================================================================
# AWS::IAM::Role custom resources + honoring a function's explicit Role
# ============================================================================
# Creates aws_iam_role for AWS::IAM::Role resources declared in the template
# (assume-role policy, inline Policies, ManagedPolicyArns), and lets a Lambda
# function use an explicit `Role:` (a shared role) instead of the per-function
# role the module creates by default.
#
# A function whose `Role` !GetAtt/!Ref points at one of these template roles is
# bound directly to the created aws_iam_role (by logical ID, recovered from the
# resolved role ARN's "role/<name>" segment). A `Role` pointing at an external
# ARN is used verbatim.

locals {
  iam_roles = {
    for logical_id, resource in local.custom_resources_raw :
    logical_id => resource
    if local._custom_resource_types[logical_id] == "AWS::IAM::Role"
    && (var.resource_types == null || contains(var.resource_types, "AWS::IAM::Role"))
  }

  # Role logical ID -> role name (RoleName if set, else the logical ID — which is
  # also what the preprocessor uses when fabricating !GetAtt <Role>.Arn, so the
  # created role's name and any GetAtt reference to it stay consistent).
  _iam_role_name = {
    for logical_id in keys(local.iam_roles) :
    logical_id => tostring(try(local._custom_resources_structure[logical_id].Properties.RoleName, logical_id))
  }

  # role name OR logical ID -> logical ID, to map a resolved role ARN back to the
  # created resource.
  _iam_role_name_to_logical = merge(
    { for logical_id in keys(local.iam_roles) : logical_id => logical_id },
    { for logical_id, nm in local._iam_role_name : nm => logical_id }
  )

  # Inline policies, keyed "<role>::<index>". Keys/name from the structural parse
  # (plan-known); the policy document from the resolved parse.
  iam_role_inline_policies = merge([
    for logical_id in keys(local.iam_roles) : {
      for idx, pol in try(local._custom_resources_structure[logical_id].Properties.Policies, []) :
      "${logical_id}::${idx}" => {
        role_id  = logical_id
        name     = tostring(try(pol.PolicyName, "policy-${idx}"))
        document = try(local.custom_resources_raw[logical_id].Properties.Policies[idx].PolicyDocument, { Version = "2012-10-17", Statement = [] })
      }
    }
  ]...)

  # Managed policy attachments, keyed "<role>::<index>".
  iam_role_managed_attachments = merge([
    for logical_id in keys(local.iam_roles) : {
      for idx, arn in try(local._custom_resources_structure[logical_id].Properties.ManagedPolicyArns, []) :
      "${logical_id}::${idx}" => {
        role_id = logical_id
        arn     = tostring(try(local.custom_resources_raw[logical_id].Properties.ManagedPolicyArns[idx], arn))
      }
    }
  ]...)

  # Whether each function declares an explicit Role (structural — gates for_each).
  _function_has_explicit_role = {
    for func_name in local._function_names :
    func_name => (
      var.config_format == "sam" && local.sam_structure != null
      ? try(local.sam_structure.Resources[func_name].Properties.Role, null) != null
      : try(local.functions_with_defaults[func_name].role, null) != null
    )
  }

  # The resolved role ARN to assign to a function that declares one: bound to the
  # created aws_iam_role when it maps to a template role, else the raw ARN.
  _function_role_arn = {
    for func_name in local._function_names :
    func_name => try(
      aws_iam_role.custom[
        local._iam_role_name_to_logical[
          regex("role/([^/]+)$", tostring(local.functions_with_defaults[func_name].role))[0]
        ]
      ].arn,
      tostring(try(local.functions_with_defaults[func_name].role, ""))
    )
    if local._function_has_explicit_role[func_name]
  }
}

resource "aws_iam_role" "custom" {
  for_each = local.iam_roles

  name = local._iam_role_name[each.key]

  assume_role_policy = jsonencode(try(
    each.value.Properties.AssumeRolePolicyDocument,
    { Version = "2012-10-17", Statement = [] }
  ))

  tags = {
    Name      = each.key
    ManagedBy = "sls.tf"
    LogicalId = each.key
    Stage     = local.provider_with_defaults.stage
  }

  depends_on = [null_resource.config_validation]
}

resource "aws_iam_role_policy" "custom" {
  for_each = local.iam_role_inline_policies

  name   = each.value.name
  role   = aws_iam_role.custom[each.value.role_id].id
  policy = jsonencode(each.value.document)
}

resource "aws_iam_role_policy_attachment" "custom_managed" {
  for_each = local.iam_role_managed_attachments

  role       = aws_iam_role.custom[each.value.role_id].name
  policy_arn = each.value.arn
}
