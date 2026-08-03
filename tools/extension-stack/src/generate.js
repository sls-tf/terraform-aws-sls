'use strict';

/**
 * Turn an sls.tf extension sidecar into a companion CloudFormation template.
 *
 * The point of the companion stack is that `sam deploy template.yaml` on its
 * own is a PARTIAL deploy — extensions are inert to CloudFormation, so it
 * succeeds and creates none of them. With a sidecar the template stays
 * pristine and the extensions become a sibling stack, so the deploy is
 * completed rather than silently short. Two `deploy` commands instead of one,
 * which is documentable and checkable in CI; the alternative is a stack that
 * quietly lacks its monitoring.
 *
 * Why CloudFormation rather than a bespoke applier: alarms and dashboards are
 * plain CFN resources. The only dynamic part is deciding WHICH ones, and that
 * happens here at generation time. Lifecycle and deletion then come free —
 * remove a group from the sidecar, regenerate, deploy, and CloudFormation
 * removes the alarms. A stateless CLI applying changes directly would have to
 * reimplement that reconciliation by hand.
 *
 * Output is JSON, not YAML: CloudFormation accepts JSON templates, and
 * emitting it needs no YAML serialiser, which keeps this tool dependency-free.
 */

// Mirrors local._alarm_class_defaults in alarm-sets.tf. Kept in step with it
// by tests/parity.test.js, which reads the Terraform source rather than
// trusting this copy.
const CLASS_DEFAULTS = {
  lambda: { namespace: 'AWS/Lambda', dimension: 'FunctionName' },
  dynamodb: { namespace: 'AWS/DynamoDB', dimension: 'TableName' },
  sqs: { namespace: 'AWS/SQS', dimension: 'QueueName' },
  sns: { namespace: 'AWS/SNS', dimension: 'TopicName' },
  s3: { namespace: 'AWS/S3', dimension: 'BucketName' },
  eventbridge: { namespace: 'AWS/Events', dimension: 'RuleName' },
  athena: { namespace: 'AWS/Athena', dimension: 'WorkGroup' },
  api_gateway: { namespace: 'AWS/ApiGateway', dimension: 'ApiName' },
};

// Mirrors local._dashboard_class_metrics in dashboard.tf.
const DASHBOARD_METRICS = {
  lambda: ['Invocations', 'Errors', 'Duration'],
  dynamodb: ['ConsumedReadCapacityUnits', 'ConsumedWriteCapacityUnits', 'ThrottledRequests'],
  sqs: ['ApproximateNumberOfMessagesVisible', 'ApproximateAgeOfOldestMessage'],
  sns: ['NumberOfMessagesPublished', 'NumberOfNotificationsFailed'],
  s3: ['AllRequests', '4xxErrors', '5xxErrors'],
  eventbridge: ['Invocations', 'FailedInvocations'],
  athena: ['QuerySuccessful', 'QueryFailed'],
  api_gateway: ['Count', '4XXError', '5XXError'],
};

// Which template resource types belong to each alarm class, and where each
// type carries its explicit physical name.
const CLASS_RESOURCE_TYPES = {
  lambda: [
    { type: 'AWS::Serverless::Function', nameProperty: 'FunctionName' },
    { type: 'AWS::Lambda::Function', nameProperty: 'FunctionName' },
  ],
  dynamodb: [{ type: 'AWS::DynamoDB::Table', nameProperty: 'TableName' }],
  sqs: [{ type: 'AWS::SQS::Queue', nameProperty: 'QueueName' }],
  sns: [{ type: 'AWS::SNS::Topic', nameProperty: 'TopicName' }],
  s3: [{ type: 'AWS::S3::Bucket', nameProperty: 'BucketName' }],
  eventbridge: [{ type: 'AWS::Events::Rule', nameProperty: 'Name' }],
  athena: [{ type: 'AWS::Athena::WorkGroup', nameProperty: 'Name' }],
  // An API name is not reliably template-derived; declare resource_names.
  api_gateway: [],
};

class GenerateError extends Error {}

/**
 * Resource names for one alarm class, from the template.
 *
 * This is where the companion stack differs fundamentally from the Terraform
 * path. The module PREDICTS names for resources that omit one, using sls.tf's
 * own convention (`${service}-${stage}-${key}`). Under `sam deploy`,
 * CloudFormation instead assigns `stack-LogicalId-AB12CD34`, so a predicted
 * name would produce alarms watching resources that do not exist — and an
 * alarm on a nonexistent dimension does not fail, it sits in INSUFFICIENT_DATA
 * forever. Silent, which is the whole thing this design is trying to stop.
 *
 * So v1 requires explicit names and says exactly which resources lack one.
 * Sourcing real names from the deployed stack (describe-stack-resources) would
 * lift the restriction and is the natural next step.
 */
function enumerateClass(template, className) {
  const types = CLASS_RESOURCE_TYPES[className];
  if (!types) {
    throw new GenerateError(
      `Unknown alarm class '${className}'. Known classes: ${Object.keys(CLASS_DEFAULTS).sort().join(', ')}.`
    );
  }

  const resources = template.Resources || {};
  const named = [];
  const unnamed = [];

  for (const [logicalId, resource] of Object.entries(resources)) {
    const match = types.find((t) => t.type === (resource && resource.Type));
    if (!match) continue;

    const name = resource.Properties && resource.Properties[match.nameProperty];
    if (typeof name === 'string' && name.length > 0) {
      named.push(name);
    } else {
      unnamed.push({ logicalId, nameProperty: match.nameProperty });
    }
  }

  return { named, unnamed };
}

function resolveGroupResourceNames(template, className, group) {
  const explicit = Array.isArray(group.resource_names) ? group.resource_names : [];
  if (explicit.length > 0) return explicit.map(String);

  const { named, unnamed } = enumerateClass(template, className);

  if (unnamed.length > 0) {
    const detail = unnamed
      .map((u) => `${u.logicalId} (no Properties.${u.nameProperty})`)
      .join(', ');
    throw new GenerateError(
      `Alarm group '${className}' auto-enumerates, but these ${className} resources have no explicit name: ${detail}. ` +
        'Under `sam deploy` CloudFormation assigns a generated physical name (stack-LogicalId-XXXXXXXX), so an alarm ' +
        'built from a predicted name would watch a resource that does not exist and sit in INSUFFICIENT_DATA silently. ' +
        `Give each resource an explicit name, or pin the group with an explicit resource_names list.`
    );
  }

  if (named.length === 0 && className === 'api_gateway') {
    throw new GenerateError(
      "Alarm group 'api_gateway' has no resource_names. An API name is not reliably derivable from the template; " +
        'list the names explicitly.'
    );
  }

  return named;
}

// Metrics may be objects or bare strings ("Errors"), matching the module.
function normaliseMetric(metric) {
  if (typeof metric === 'string') return { name: metric };
  return metric || {};
}

function pick(...values) {
  for (const v of values) {
    if (v !== undefined && v !== null) return v;
  }
  return undefined;
}

// CloudFormation logical IDs are alphanumeric only.
function toLogicalId(...parts) {
  const raw = parts.join('-');
  const cleaned = raw
    .split(/[^a-zA-Z0-9]+/)
    .filter(Boolean)
    .map((s) => s.charAt(0).toUpperCase() + s.slice(1))
    .join('');
  return cleaned || 'Resource';
}

function buildAlarms(template, alarms) {
  const resources = {};
  const defaults = alarms.defaults || {};
  const groups = alarms.groups || {};

  for (const [className, group] of Object.entries(groups)) {
    const classDefault = CLASS_DEFAULTS[className];
    if (!classDefault && !(group.namespace && group.dimension)) {
      throw new GenerateError(
        `Alarm group '${className}' is not a known class and does not set both 'namespace' and 'dimension'. ` +
          `Known classes: ${Object.keys(CLASS_DEFAULTS).sort().join(', ')}.`
      );
    }

    const namespace = pick(group.namespace, classDefault && classDefault.namespace);
    const dimension = pick(group.dimension, group.dimension_key, classDefault && classDefault.dimension);
    const actions = pick(group.actions, defaults.actions) || [];
    const resourceNames = resolveGroupResourceNames(template, className, group);

    for (const rawMetric of group.metrics || []) {
      const metric = normaliseMetric(rawMetric);

      // Mirrors the same fallback chain as alarm-sets.tf: per-metric, then
      // group, then the hard default.
      const anomalyDetection = Boolean(
        pick(
          metric.anomalyDetection,
          metric.anomaly_detection,
          group.anomalyDetection,
          group.anomaly_detection,
          false
        )
      );
      const anomalyBand = pick(
        metric.anomalyBandWidth,
        metric.anomaly_band_width,
        group.anomalyBandWidth,
        group.anomaly_band_width,
        2
      );
      const threshold = pick(metric.threshold, group.threshold);
      const period = pick(metric.period, group.period, 300);
      const statistic = pick(metric.statistic, group.statistic, 'Sum');

      // A static-threshold alarm without a threshold is not a CloudFormation
      // template CFN will accept, and the deploy would fail AFTER the main
      // stack had already gone out. Refuse here, where it is cheap.
      if (!anomalyDetection && (threshold === undefined || threshold === null)) {
        throw new GenerateError(
          `Alarm group '${className}' metric '${metric.name}' has no threshold. CloudFormation requires Threshold on a ` +
            'static-threshold alarm, so this template would be rejected at deploy time — after the SAM stack it ' +
            'accompanies had already been deployed. Set a threshold, or set anomalyDetection: true to alarm on a band.'
        );
      }

      for (const resourceName of resourceNames) {
        // Same "<group>-<metric>-<resource>" alarm name the Terraform path
        // uses, so the two produce identically-named alarms.
        const alarmName = `${className}-${metric.name}-${resourceName}`;

        const common = {
          AlarmName: alarmName,
          AlarmDescription: pick(metric.description, 'Managed by sls.tf alarm set'),
          EvaluationPeriods: pick(
            metric.evaluationPeriods,
            metric.evaluation_periods,
            group.evaluationPeriods,
            group.evaluation_periods,
            1
          ),
          DatapointsToAlarm: pick(
            metric.datapointsToAlarm,
            metric.datapoints_to_alarm,
            group.datapointsToAlarm,
            group.datapoints_to_alarm
          ),
          TreatMissingData: pick(
            metric.treatMissingData,
            metric.treat_missing_data,
            group.treatMissingData,
            group.treat_missing_data,
            'missing'
          ),
          AlarmActions: actions.length > 0 ? actions : undefined,
        };

        // Anomaly-detection alarms compare the metric against an
        // ANOMALY_DETECTION_BAND expression instead of a static threshold. The
        // two forms are mutually exclusive: namespace/metric/period/statistic
        // move inside the Metrics array, and ThresholdMetricId replaces
        // Threshold. Mirrors the metric_query blocks in alarm-sets.tf.
        const properties = anomalyDetection
          ? {
              ...common,
              ComparisonOperator: 'LessThanLowerOrGreaterThanUpperThreshold',
              ThresholdMetricId: 'ad1',
              Metrics: [
                {
                  Id: 'm1',
                  ReturnData: true,
                  MetricStat: {
                    Metric: {
                      Namespace: namespace,
                      MetricName: metric.name,
                      Dimensions: [{ Name: dimension, Value: resourceName }],
                    },
                    Period: period,
                    Stat: statistic,
                  },
                },
                {
                  Id: 'ad1',
                  Expression: `ANOMALY_DETECTION_BAND(m1, ${anomalyBand})`,
                  Label: `${metric.name} (expected band)`,
                  ReturnData: true,
                },
              ],
            }
          : {
              ...common,
              Namespace: namespace,
              MetricName: metric.name,
              Dimensions: [{ Name: dimension, Value: resourceName }],
              Period: period,
              Statistic: statistic,
              Threshold: threshold,
              ComparisonOperator: pick(
                metric.comparisonOperator,
                metric.comparison_operator,
                group.comparisonOperator,
                group.comparison_operator,
                'GreaterThanOrEqualToThreshold'
              ),
            };

        resources[toLogicalId('Alarm', className, metric.name, resourceName)] = {
          Type: 'AWS::CloudWatch::Alarm',
          Properties: properties,
        };
      }
    }
  }

  return resources;
}

function buildDashboard(template, dashboard, alarms) {
  const services = dashboard.services || Object.keys(DASHBOARD_METRICS);
  const widgets = [];
  let y = 0;

  for (const className of services) {
    const metrics = DASHBOARD_METRICS[className];
    if (!metrics) {
      throw new GenerateError(
        `Dashboard service '${className}' is not a known class. Known: ${Object.keys(DASHBOARD_METRICS).sort().join(', ')}.`
      );
    }

    const classDefault = CLASS_DEFAULTS[className];

    // An explicit alarm-group resource_names list wins, mirroring dashboard.tf
    // — that is how classes without auto-enumeration get their names.
    const group = (alarms && alarms.groups && alarms.groups[className]) || {};
    const names =
      Array.isArray(group.resource_names) && group.resource_names.length > 0
        ? group.resource_names.map(String)
        : resolveGroupResourceNames(template, className, {});

    if (names.length === 0) continue;

    const rows = [];
    for (const name of names) {
      for (const metric of metrics) {
        rows.push([classDefault.namespace, metric, classDefault.dimension, name]);
      }
    }

    widgets.push({
      type: 'metric',
      x: 0,
      y,
      width: 24,
      height: 6,
      properties: { title: className, view: 'timeSeries', stacked: false, metrics: rows },
    });
    y += 6;
  }

  return {
    [toLogicalId('Dashboard', dashboard.name || 'sls-tf')]: {
      Type: 'AWS::CloudWatch::Dashboard',
      Properties: {
        DashboardName: dashboard.name,
        DashboardBody: JSON.stringify({ widgets }),
      },
    },
  };
}

/**
 * @param {object} template  parsed SAM/CFN template
 * @param {object} sidecar   parsed slstf.yaml
 * @returns {object} a CloudFormation template
 */
function generate(template, sidecar) {
  if (!sidecar || typeof sidecar !== 'object') {
    throw new GenerateError('Sidecar is empty or not a mapping.');
  }

  // CustomDomain needs the deployed API's id, which is not in the template and
  // is not knowable at generation time. Refusing loudly beats emitting a stack
  // that cannot work.
  if (sidecar.CustomDomain || sidecar.customDomain) {
    throw new GenerateError(
      'CustomDomain is not supported in a companion stack yet: it needs the deployed REST API id, which is not in ' +
        'the template. Deploy the domain with Terraform, or wait for stack-sourced discovery.'
    );
  }

  const known = ['Alarms', 'Dashboard'];
  const unknown = Object.keys(sidecar).filter((k) => !known.includes(k));
  if (unknown.length > 0) {
    throw new GenerateError(
      `Unknown sls.tf extension(s) in the sidecar: ${unknown.join(', ')}. This generator supports: ${known.join(', ')}.`
    );
  }

  let resources = {};
  if (sidecar.Alarms) resources = { ...resources, ...buildAlarms(template, sidecar.Alarms) };
  if (sidecar.Dashboard) {
    resources = { ...resources, ...buildDashboard(template, sidecar.Dashboard, sidecar.Alarms) };
  }

  if (Object.keys(resources).length === 0) {
    throw new GenerateError('The sidecar produced no resources — nothing to deploy.');
  }

  return {
    AWSTemplateFormatVersion: '2010-09-09',
    Description:
      'sls.tf extensions companion stack. Generated from a sidecar — deploy alongside the SAM template it accompanies; ' +
      'the SAM template alone is an incomplete deploy.',
    Resources: resources,
  };
}

module.exports = { generate, GenerateError, CLASS_DEFAULTS, DASHBOARD_METRICS, enumerateClass };
