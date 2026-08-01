'use strict';

const { test, describe } = require('node:test');
const assert = require('node:assert');

const { generate, GenerateError } = require('../src/generate');

const TEMPLATE = {
  Resources: {
    Ingest: {
      Type: 'AWS::Serverless::Function',
      Properties: { FunctionName: 'svc-dev-ingest', Handler: 'h.i' },
    },
    Process: {
      Type: 'AWS::Serverless::Function',
      Properties: { FunctionName: 'svc-dev-process', Handler: 'h.p' },
    },
    Events: {
      Type: 'AWS::DynamoDB::Table',
      Properties: { TableName: 'svc-events-dev' },
    },
  },
};

const ALARMS = {
  defaults: { actions: ['arn:aws:sns:us-east-1:123456789012:ops'] },
  groups: {
    lambda: {
      resource_names: [],
      metrics: [
        { name: 'Errors', threshold: 1, comparisonOperator: 'GreaterThanThreshold' },
        'Throttles',
      ],
    },
  },
};

describe('alarm generation', () => {
  test('one alarm per (group, metric, resource)', () => {
    const stack = generate(TEMPLATE, { Alarms: ALARMS });
    const alarms = Object.values(stack.Resources).filter((r) => r.Type === 'AWS::CloudWatch::Alarm');
    // 2 metrics x 2 functions
    assert.strictEqual(alarms.length, 4);
  });

  test('alarm names match the Terraform path exactly', () => {
    // The two appliers must not produce differently-named alarms for the same
    // config, or moving between them churns every alarm.
    const stack = generate(TEMPLATE, { Alarms: ALARMS });
    const names = Object.values(stack.Resources)
      .filter((r) => r.Type === 'AWS::CloudWatch::Alarm')
      .map((r) => r.Properties.AlarmName)
      .sort();
    assert.deepStrictEqual(names, [
      'lambda-Errors-svc-dev-ingest',
      'lambda-Errors-svc-dev-process',
      'lambda-Throttles-svc-dev-ingest',
      'lambda-Throttles-svc-dev-process',
    ]);
  });

  test('bare string metrics are accepted, like the module', () => {
    const stack = generate(TEMPLATE, { Alarms: ALARMS });
    const throttles = Object.values(stack.Resources).find(
      (r) => r.Properties.AlarmName === 'lambda-Throttles-svc-dev-ingest'
    );
    assert.strictEqual(throttles.Properties.MetricName, 'Throttles');
    // Falls back to the same hard defaults as alarm-sets.tf.
    assert.strictEqual(throttles.Properties.Period, 300);
    assert.strictEqual(throttles.Properties.Statistic, 'Sum');
    assert.strictEqual(throttles.Properties.ComparisonOperator, 'GreaterThanOrEqualToThreshold');
    assert.strictEqual(throttles.Properties.EvaluationPeriods, 1);
    assert.strictEqual(throttles.Properties.TreatMissingData, 'missing');
  });

  test('group actions override defaults.actions', () => {
    const stack = generate(TEMPLATE, {
      Alarms: {
        defaults: { actions: ['arn:default'] },
        groups: {
          lambda: { resource_names: ['pinned'], actions: ['arn:group'], metrics: ['Errors'] },
        },
      },
    });
    const alarm = Object.values(stack.Resources)[0];
    assert.deepStrictEqual(alarm.Properties.AlarmActions, ['arn:group']);
  });

  test('explicit resource_names bypass enumeration', () => {
    const stack = generate(TEMPLATE, {
      Alarms: { groups: { api_gateway: { resource_names: ['my-api'], metrics: ['5XXError'] } } },
    });
    const alarm = Object.values(stack.Resources)[0];
    assert.strictEqual(alarm.Properties.Namespace, 'AWS/ApiGateway');
    assert.deepStrictEqual(alarm.Properties.Dimensions, [{ Name: 'ApiName', Value: 'my-api' }]);
  });

  test('a custom class needs both namespace and dimension', () => {
    assert.throws(
      () => generate(TEMPLATE, { Alarms: { groups: { custom: { metrics: ['X'] } } } }),
      (e) => e instanceof GenerateError && /not a known class/.test(e.message)
    );
  });
});

describe('the explicit-name requirement', () => {
  // The crux of the companion-stack path. The Terraform module PREDICTS names
  // for unnamed resources using sls.tf's convention; CloudFormation assigns
  // stack-LogicalId-XXXXXXXX instead. An alarm built on a predicted name would
  // watch nothing and sit in INSUFFICIENT_DATA — silent, which is the failure
  // this whole design exists to remove.
  const UNNAMED = {
    Resources: {
      Ingest: { Type: 'AWS::Serverless::Function', Properties: { Handler: 'h.i' } },
      Named: { Type: 'AWS::Serverless::Function', Properties: { FunctionName: 'ok', Handler: 'h.n' } },
    },
  };

  test('auto-enumeration refuses resources without an explicit name', () => {
    assert.throws(
      () => generate(UNNAMED, { Alarms: { groups: { lambda: { metrics: ['Errors'] } } } }),
      (e) => e instanceof GenerateError && /no explicit name/.test(e.message)
    );
  });

  test('the error names the offending resource and the missing property', () => {
    try {
      generate(UNNAMED, { Alarms: { groups: { lambda: { metrics: ['Errors'] } } } });
      assert.fail('should have thrown');
    } catch (e) {
      assert.match(e.message, /Ingest \(no Properties\.FunctionName\)/);
      assert.doesNotMatch(e.message, /Named/, 'the named resource is not at fault');
      assert.match(e.message, /INSUFFICIENT_DATA/, 'explains why it matters');
    }
  });

  test('an explicit resource_names list sidesteps it', () => {
    const stack = generate(UNNAMED, {
      Alarms: { groups: { lambda: { resource_names: ['whatever'], metrics: ['Errors'] } } },
    });
    assert.strictEqual(Object.keys(stack.Resources).length, 1);
  });
});

describe('dashboard generation', () => {
  test('one widget per service class, metrics per resource', () => {
    const stack = generate(TEMPLATE, { Dashboard: { name: 'monitoring', services: ['lambda'] } });
    const dash = Object.values(stack.Resources).find((r) => r.Type === 'AWS::CloudWatch::Dashboard');
    assert.strictEqual(dash.Properties.DashboardName, 'monitoring');

    const body = JSON.parse(dash.Properties.DashboardBody);
    assert.strictEqual(body.widgets.length, 1);
    // 3 lambda metrics x 2 functions
    assert.strictEqual(body.widgets[0].properties.metrics.length, 6);
    assert.deepStrictEqual(body.widgets[0].properties.metrics[0], [
      'AWS/Lambda',
      'Invocations',
      'FunctionName',
      'svc-dev-ingest',
    ]);
  });

  test('an alarm group resource_names list supplies names the template cannot', () => {
    const stack = generate(TEMPLATE, {
      Dashboard: { name: 'd', services: ['api_gateway'] },
      Alarms: { groups: { api_gateway: { resource_names: ['my-api'], metrics: ['Count'] } } },
    });
    const dash = Object.values(stack.Resources).find((r) => r.Type === 'AWS::CloudWatch::Dashboard');
    const body = JSON.parse(dash.Properties.DashboardBody);
    assert.deepStrictEqual(body.widgets[0].properties.metrics[0], [
      'AWS/ApiGateway',
      'Count',
      'ApiName',
      'my-api',
    ]);
  });

  test('an unknown service class is rejected', () => {
    assert.throws(
      () => generate(TEMPLATE, { Dashboard: { services: ['nope'] } }),
      (e) => e instanceof GenerateError && /not a known class/.test(e.message)
    );
  });
});

describe('refusals', () => {
  test('CustomDomain is refused rather than half-generated', () => {
    // It needs the deployed REST API id, which is not in the template. A stack
    // that cannot work is worse than a clear refusal.
    assert.throws(
      () => generate(TEMPLATE, { CustomDomain: { domainName: 'x.example.com' } }),
      (e) => e instanceof GenerateError && /not supported in a companion stack yet/.test(e.message)
    );
  });

  test('unknown sidecar keys are refused, as they are in the module', () => {
    assert.throws(
      () => generate(TEMPLATE, { Alarm: {} }),
      (e) => e instanceof GenerateError && /Unknown sls\.tf extension\(s\)/.test(e.message)
    );
  });

  test('a sidecar that produces nothing is an error, not an empty stack', () => {
    assert.throws(
      () => generate(TEMPLATE, { Alarms: { groups: {} } }),
      (e) => e instanceof GenerateError && /no resources/.test(e.message)
    );
  });
});

describe('output shape', () => {
  test('is a deployable CloudFormation template', () => {
    const stack = generate(TEMPLATE, { Alarms: ALARMS });
    assert.strictEqual(stack.AWSTemplateFormatVersion, '2010-09-09');
    assert.match(stack.Description, /incomplete deploy/);
    assert.ok(Object.keys(stack.Resources).length > 0);
  });

  test('logical IDs are alphanumeric', () => {
    const stack = generate(TEMPLATE, { Alarms: ALARMS });
    for (const id of Object.keys(stack.Resources)) {
      assert.match(id, /^[A-Za-z0-9]+$/, `${id} is not a valid CloudFormation logical ID`);
    }
  });

  test('logical IDs are unique across a realistic config', () => {
    const stack = generate(TEMPLATE, {
      Alarms: ALARMS,
      Dashboard: { name: 'd', services: ['lambda', 'dynamodb'] },
    });
    const ids = Object.keys(stack.Resources);
    assert.strictEqual(ids.length, new Set(ids).size);
  });
});
