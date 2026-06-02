#!/usr/bin/env node
'use strict';

// SAM YAML preprocessor for sls.tf
//
// Terraform's yamldecode() raises an error on CloudFormation intrinsic function
// tags (!Ref, !Sub, !If, etc.) instead of stripping them.  This script uses
// js-yaml with a custom schema that captures tagged values as structured objects
// {__cfn: tag, v: value}, then fully evaluates all intrinsic functions so the
// output is a plain JSON-serialisable object with no remaining CFN constructs.
//
// Protocol: Terraform external data source (JSON on stdin → JSON on stdout).
//
// Input fields (all optional except config_path):
//   config_path  — path to the SAM YAML file
//   parameters   — JSON-encoded map of parameter overrides (from sam_template_parameters)
//   region       — AWS region string (for AWS::Region pseudo-param)
//   account_id   — AWS account ID string (for AWS::AccountId pseudo-param)
//   strict       — "true"/"false" — throw on unresolved refs (default: "true")

const yaml = require('js-yaml');
const fs   = require('fs');

// ============================================================================
// YAML schema: capture every CFN tag as {__cfn: tag, v: value}
// ============================================================================

const CFN_TAGS = [
  'Ref', 'Sub', 'If', 'And', 'Or', 'Not', 'Equals', 'Select',
  'Split', 'Join', 'FindInMap', 'GetAtt', 'GetAZs', 'ImportValue',
  'Base64', 'Cidr', 'Condition', 'Transform',
];

const types = CFN_TAGS.flatMap(tag =>
  ['scalar', 'sequence', 'mapping'].map(kind =>
    new yaml.Type(`!${tag}`, {
      kind,
      construct: d => ({ __cfn: tag, v: d }),
    })
  )
);

const CFN_SCHEMA = yaml.DEFAULT_SCHEMA.extend(types);

// ============================================================================
// Intrinsic function evaluator
// ============================================================================

const NOVALUE = Symbol('AWS::NoValue');

function isCfn(v, tag) {
  return v !== null && typeof v === 'object' && v.__cfn === tag;
}

function isAnyCfn(v) {
  return v !== null && typeof v === 'object' && typeof v.__cfn === 'string';
}

/**
 * Deep-evaluate a parsed YAML value:
 *   - Objects with __cfn: evaluate the intrinsic
 *   - Plain objects: evaluate each value, omit keys whose result is NOVALUE
 *   - Arrays: evaluate each element, filter NOVALUE entries
 *   - Primitives: return as-is
 */
function evaluate(node, ctx) {
  if (node === null || node === undefined) return node;

  if (isAnyCfn(node)) {
    return evalIntrinsic(node.__cfn, node.v, ctx);
  }

  if (Array.isArray(node)) {
    const result = [];
    for (const item of node) {
      const val = evaluate(item, ctx);
      if (val !== NOVALUE) result.push(val);
    }
    return result;
  }

  if (typeof node === 'object') {
    const result = {};
    for (const [k, v] of Object.entries(node)) {
      const val = evaluate(v, ctx);
      if (val !== NOVALUE) result[k] = val;
    }
    return result;
  }

  return node;
}

function evalIntrinsic(tag, value, ctx) {
  switch (tag) {
    case 'Ref':       return evalRef(value, ctx);
    case 'Sub':       return evalSub(value, ctx);
    case 'GetAtt':    return evalGetAtt(value, ctx);
    case 'If':        return evalIf(value, ctx);
    case 'And':       return evalAnd(value, ctx);
    case 'Or':        return evalOr(value, ctx);
    case 'Not':       return evalNot(value, ctx);
    case 'Equals':    return evalEquals(value, ctx);
    case 'Select':    return evalSelect(value, ctx);
    case 'Join':      return evalJoin(value, ctx);
    case 'Split':     return evalSplit(value, ctx);
    case 'FindInMap': return evalFindInMap(value, ctx);
    case 'Condition': return evalConditionRef(value, ctx);
    // Pass-through for unsupported tags: evaluate inner value
    default:          return evaluate(value, ctx);
  }
}

function evalRef(value, ctx) {
  const name = typeof value === 'string' ? value : String(value);
  if (name === 'AWS::NoValue') return NOVALUE;
  if (Object.prototype.hasOwnProperty.call(ctx.params, name)) {
    return ctx.params[name];
  }
  return unresolved('Ref', name, ctx);
}

function evalSub(value, ctx) {
  let template, localVars = {};

  if (typeof value === 'string') {
    template = value;
  } else if (Array.isArray(value) && value.length >= 1) {
    // 2-argument form: [template, {var: value, ...}]
    template = typeof value[0] === 'string' ? value[0] : evaluate(value[0], ctx);
    if (value[1] && typeof value[1] === 'object' && !Array.isArray(value[1])) {
      // Evaluate each local var substitution
      for (const [k, v] of Object.entries(value[1])) {
        localVars[k] = evaluate(v, ctx);
      }
    }
  } else {
    template = String(evaluate(value, ctx));
  }

  // Merge local vars on top of params (local vars take precedence)
  const subCtx = { ...ctx, params: { ...ctx.params, ...localVars } };

  // Interpolate ${...} sequences
  return template.replace(/\$\{([^}]+)\}/g, (match, expr) => {
    // ${LogicalId.Attr} form — try GetAtt first
    if (expr.includes('.')) {
      const dotIdx = expr.indexOf('.');
      const logicalId = expr.slice(0, dotIdx);
      const attr = expr.slice(dotIdx + 1);
      const attResult = evalGetAtt([logicalId, attr], subCtx);
      if (attResult !== null && attResult !== undefined) return String(attResult);
    }
    // ${ParamName} form
    if (Object.prototype.hasOwnProperty.call(subCtx.params, expr)) {
      const val = subCtx.params[expr];
      return val === null || val === undefined ? '' : String(val);
    }
    return unresolved('Sub', expr, subCtx) || match;
  });
}

function evalGetAtt(value, ctx) {
  let logicalId, attr;
  if (typeof value === 'string') {
    const dot = value.indexOf('.');
    logicalId = value.slice(0, dot);
    attr      = value.slice(dot + 1);
  } else if (Array.isArray(value) && value.length >= 2) {
    logicalId = String(evaluate(value[0], ctx));
    attr      = String(evaluate(value[1], ctx));
  } else {
    return unresolved('GetAtt', String(value), ctx);
  }
  const key = `${logicalId}.${attr}`;
  if (ctx.resourceAttrs && Object.prototype.hasOwnProperty.call(ctx.resourceAttrs, key)) {
    return ctx.resourceAttrs[key];
  }
  return unresolved('GetAtt', key, ctx);
}

function evalIf(value, ctx) {
  if (!Array.isArray(value) || value.length !== 3) {
    return unresolved('If', String(value), ctx);
  }
  const [condName, ifTrue, ifFalse] = value;
  const condResult = resolveCondition(condName, ctx);
  const branch = condResult ? evaluate(ifTrue, ctx) : evaluate(ifFalse, ctx);
  if (branch === NOVALUE) return NOVALUE;
  return branch;
}

function evalAnd(value, ctx) {
  if (!Array.isArray(value)) return false;
  return value.every(v => isTruthy(evaluateConditionValue(v, ctx)));
}

function evalOr(value, ctx) {
  if (!Array.isArray(value)) return false;
  return value.some(v => isTruthy(evaluateConditionValue(v, ctx)));
}

function evalNot(value, ctx) {
  const inner = Array.isArray(value) ? value[0] : value;
  return !isTruthy(evaluateConditionValue(inner, ctx));
}

function evalEquals(value, ctx) {
  if (!Array.isArray(value) || value.length !== 2) return false;
  const a = evaluate(value[0], ctx);
  const b = evaluate(value[1], ctx);
  return String(a) === String(b);
}

function evalSelect(value, ctx) {
  if (!Array.isArray(value) || value.length !== 2) return null;
  const idx  = Number(evaluate(value[0], ctx));
  const list = evaluate(value[1], ctx);
  if (Array.isArray(list)) return list[idx] !== undefined ? list[idx] : null;
  // If the list resolved to a string (CommaDelimitedList), split it
  if (typeof list === 'string') {
    const parts = list.split(',').map(s => s.trim());
    return parts[idx] !== undefined ? parts[idx] : null;
  }
  return null;
}

function evalJoin(value, ctx) {
  if (!Array.isArray(value) || value.length !== 2) return '';
  const delim = String(evaluate(value[0], ctx));
  const list  = evaluate(value[1], ctx);
  if (!Array.isArray(list)) return String(list);
  return list
    .filter(v => v !== null && v !== undefined && v !== NOVALUE)
    .map(v => String(v))
    .join(delim);
}

function evalSplit(value, ctx) {
  if (!Array.isArray(value) || value.length !== 2) return [];
  const delim = String(evaluate(value[0], ctx));
  const str   = String(evaluate(value[1], ctx));
  return str.split(delim);
}

function evalFindInMap(value, ctx) {
  if (!Array.isArray(value) || value.length !== 3) return null;
  const [mapName, key1, key2] = value.map(v => evaluate(v, ctx));
  try {
    return ctx.mappings[String(mapName)][String(key1)][String(key2)];
  } catch (_) {
    return unresolved('FindInMap', `${mapName}.${key1}.${key2}`, ctx);
  }
}

function evalConditionRef(value, ctx) {
  return resolveCondition(typeof value === 'string' ? value : String(value), ctx);
}

// ============================================================================
// Condition evaluation helpers
// ============================================================================

function resolveCondition(name, ctx) {
  if (Object.prototype.hasOwnProperty.call(ctx.conditions, name)) {
    return ctx.conditions[name];
  }
  // Not yet resolved — evaluate it now from template Conditions section
  const condDef = ctx.conditionDefs && ctx.conditionDefs[name];
  if (condDef !== undefined) {
    const result = isTruthy(evaluateConditionValue(condDef, ctx));
    ctx.conditions[name] = result;
    return result;
  }
  return true; // unknown condition defaults to true (inclusive)
}

function evaluateConditionValue(v, ctx) {
  if (v === null || v === undefined) return false;
  if (isAnyCfn(v)) return evalIntrinsic(v.__cfn, v.v, ctx);
  if (typeof v === 'boolean') return v;
  if (typeof v === 'string') {
    // Could be a bare condition name in an And/Or/Not list
    if (Object.prototype.hasOwnProperty.call(ctx.conditions, v)) return ctx.conditions[v];
  }
  return isTruthy(evaluate(v, ctx));
}

function isTruthy(v) {
  if (v === null || v === undefined || v === '' || v === false) return false;
  if (typeof v === 'string') return v.toLowerCase() !== 'false';
  return Boolean(v);
}

// ============================================================================
// Unresolved-value handling
// ============================================================================

function unresolved(tag, name, ctx) {
  if (ctx.strict) {
    throw new Error(`Unresolved CFN intrinsic: !${tag} ${name}`);
  }
  return `__UNRESOLVED__!${tag} ${name}`;
}

// ============================================================================
// Resource attribute pre-computation for !GetAtt resolution
// ============================================================================

// Known name-property keys per resource type, in preference order.
const RESOURCE_NAME_PROPS = {
  'AWS::DynamoDB::Table':        ['TableName'],
  'AWS::Serverless::SimpleTable':['TableName'],
  'AWS::SQS::Queue':             ['QueueName'],
  'AWS::SNS::Topic':             ['TopicName'],
  'AWS::S3::Bucket':             ['BucketName'],
  'AWS::Lambda::Function':       ['FunctionName'],
  'AWS::Serverless::Function':   ['FunctionName'],
  'AWS::SecretsManager::Secret': ['Name'],
  'AWS::IAM::Role':              ['RoleName'],
  'AWS::KMS::Key':               [],               // auto-generated, no name prop
  'AWS::RDS::DBCluster':         ['DBClusterIdentifier'],
};

/**
 * Derive a resource name by evaluating its name property using only params
 * (no resourceAttrs yet). Falls back to the logical ID if unresolvable.
 */
function resolveResourceName(resource, logicalId, nameCtx) {
  const type  = resource && resource.Type;
  const props = resource && resource.Properties;
  const namePropKeys = (type && RESOURCE_NAME_PROPS[type]) || [];

  for (const key of namePropKeys) {
    const raw = props && props[key];
    if (raw === undefined || raw === null) continue;
    try {
      const resolved = evaluate(raw, nameCtx);
      if (typeof resolved === 'string' && resolved) return resolved;
    } catch (_) {}
  }
  return logicalId;
}

/**
 * Build a map of "LogicalId.Attr" → value for every resource in the template
 * whose ARN/attributes can be derived from its name and the AWS partition info.
 *
 * Called before the main evaluation so that !GetAtt references inside the
 * template (e.g. in IAM Policy Resources) resolve to real-looking ARNs rather
 * than erroring or producing marker strings.
 *
 * For resources with auto-generated names (no name property specified) the
 * logical ID is used as the name, matching the fallback convention used by the
 * rest of sls-tf when creating those resources.
 */
function buildResourceAttrs(resources, region, accountId, nameCtx) {
  const attrs = {};

  for (const [logicalId, resource] of Object.entries(resources || {})) {
    const type = resource && resource.Type;
    if (!type) continue;

    const name = resolveResourceName(resource, logicalId, nameCtx);

    switch (type) {
      case 'AWS::DynamoDB::Table':
      case 'AWS::Serverless::SimpleTable': {
        const arn = `arn:aws:dynamodb:${region}:${accountId}:table/${name}`;
        attrs[`${logicalId}.Arn`]       = arn;
        // StreamArn includes a timestamp that's unknowable at plan time;
        // use a wildcard suffix so IAM policy ARNs evaluate to something usable.
        attrs[`${logicalId}.StreamArn`] = `${arn}/stream/*`;
        break;
      }
      case 'AWS::SQS::Queue': {
        const arn = `arn:aws:sqs:${region}:${accountId}:${name}`;
        attrs[`${logicalId}.Arn`]       = arn;
        attrs[`${logicalId}.QueueUrl`]  = `https://sqs.${region}.amazonaws.com/${accountId}/${name}`;
        attrs[`${logicalId}.QueueName`] = name;
        break;
      }
      case 'AWS::SNS::Topic': {
        attrs[`${logicalId}.TopicArn`]  = `arn:aws:sns:${region}:${accountId}:${name}`;
        break;
      }
      case 'AWS::S3::Bucket': {
        const bucketName = name.toLowerCase(); // S3 names must be lowercase
        const arn = `arn:aws:s3:::${bucketName}`;
        attrs[`${logicalId}.Arn`]        = arn;
        attrs[`${logicalId}.DomainName`] = `${bucketName}.s3.amazonaws.com`;
        attrs[`${logicalId}.WebsiteURL`] = `http://${bucketName}.s3-website-${region}.amazonaws.com`;
        break;
      }
      case 'AWS::Lambda::Function':
      case 'AWS::Serverless::Function': {
        attrs[`${logicalId}.Arn`] = `arn:aws:lambda:${region}:${accountId}:function:${name}`;
        break;
      }
      case 'AWS::SecretsManager::Secret': {
        // The actual ARN has a random suffix; IAM policies should use a wildcard.
        attrs[`${logicalId}.Id`]  = `arn:aws:secretsmanager:${region}:${accountId}:secret:${name}-*`;
        attrs[`${logicalId}.Arn`] = `arn:aws:secretsmanager:${region}:${accountId}:secret:${name}-*`;
        break;
      }
      case 'AWS::IAM::Role': {
        attrs[`${logicalId}.Arn`]      = `arn:aws:iam::${accountId}:role/${name}`;
        attrs[`${logicalId}.RoleId`]   = logicalId;
        attrs[`${logicalId}.RoleName`] = name;
        break;
      }
      case 'AWS::RDS::DBCluster': {
        // Endpoint addresses are only known after cluster creation.
        // Leave them unresolved so strict mode can catch unexpected references.
        break;
      }
      // All other types: no predictable attributes — will be caught by strict mode
      // or produce a marker string in non-strict mode.
    }
  }

  return attrs;
}

// ============================================================================
// Main evaluation entry point
// ============================================================================

function evaluateTemplate(parsed, opts) {
  const {
    parameters: paramOverrides = {},
    region      = 'us-east-1',
    accountId   = '000000000000',
    stackName   = 'sam-stack',
    strict      = false,
  } = opts;

  // Build parameter map: template defaults → user overrides → pseudo-params
  const templateParams = {};
  for (const [k, def] of Object.entries(parsed.Parameters || {})) {
    if (def && def.Default !== undefined) {
      templateParams[k] = String(def.Default);
    }
  }
  const params = {
    ...templateParams,
    ...paramOverrides,
    'AWS::Region':     region,
    'AWS::AccountId':  accountId,
    'AWS::Partition':  'aws',
    'AWS::URLSuffix':  'amazonaws.com',
    'AWS::StackName':  stackName,
    // AWS::NoValue is handled specially via the NOVALUE sentinel
  };

  const conditionDefs = parsed.Conditions || {};
  const conditions    = {};
  const mappings      = parsed.Mappings || {};

  // Name-only context (no resourceAttrs, non-strict) used to resolve resource
  // name properties before the full evaluation so !GetAtt can be pre-populated.
  const nameCtx = { params, conditionDefs, conditions, mappings, resourceAttrs: {}, strict: false };

  // Pre-evaluate all conditions so mutual references resolve correctly.
  // Use nameCtx here — conditions don't reference resource attributes.
  for (const name of Object.keys(conditionDefs)) {
    if (!Object.prototype.hasOwnProperty.call(conditions, name)) {
      resolveCondition(name, nameCtx);
    }
  }

  // Derive resource attributes (ARNs etc.) from the raw Resources section so
  // !GetAtt references later in the full evaluation can be resolved.
  const resourceAttrs = buildResourceAttrs(parsed.Resources, region, accountId, nameCtx);

  const ctx = { params, conditionDefs, conditions, mappings, resourceAttrs, strict };

  // Deep-evaluate the entire template
  const evaluated = evaluate(parsed, ctx);

  // Filter resources whose Condition evaluates to false
  if (evaluated && evaluated.Resources) {
    for (const [logicalId, resource] of Object.entries(evaluated.Resources)) {
      if (resource && typeof resource.Condition === 'string') {
        const condName = resource.Condition;
        if (conditions[condName] === false) {
          delete evaluated.Resources[logicalId];
        }
      }
    }
  }

  return evaluated;
}

// ============================================================================
// stdin → stdout protocol
// ============================================================================

let input = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', chunk => { input += chunk; });
process.stdin.on('end', () => {
  try {
    const {
      config_path,
      parameters,
      region,
      account_id,
      strict = 'true',
    } = JSON.parse(input || '{}');

    if (!config_path || !fs.existsSync(config_path)) {
      process.stdout.write(JSON.stringify({ content: '', error: `File not found: ${config_path || '(empty)'}` }));
      return;
    }

    const raw    = fs.readFileSync(config_path, 'utf8');
    const parsed = yaml.load(raw, { schema: CFN_SCHEMA });

    let paramOverrides = {};
    if (parameters) {
      try { paramOverrides = JSON.parse(parameters); } catch (_) {}
    }

    const evaluated = evaluateTemplate(parsed, {
      parameters: paramOverrides,
      region:     region     || 'us-east-1',
      accountId:  account_id || '000000000000',
      strict:     strict === 'true',
    });

    process.stdout.write(JSON.stringify({ content: JSON.stringify(evaluated), error: '' }));
  } catch (e) {
    process.stdout.write(JSON.stringify({ content: '', error: e.message }));
  }
});
