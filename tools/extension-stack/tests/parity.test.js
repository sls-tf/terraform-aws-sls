'use strict';

/**
 * The generator holds its own copies of the class defaults and dashboard
 * metrics, because it cannot read Terraform locals. Copies drift. These tests
 * read the Terraform source and fail when it moves, so the two appliers cannot
 * silently disagree about what an alarm set means.
 */

const { test, describe } = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const path = require('path');

const { CLASS_DEFAULTS, DASHBOARD_METRICS } = require('../src/generate');

const ROOT = path.join(__dirname, '../../..');

function readTf(file) {
  return fs.readFileSync(path.join(ROOT, file), 'utf8');
}

// Parses a `key = { namespace = "X", dimension = "Y" }` block body.
function parseHclMapBlock(source, localName) {
  const start = source.indexOf(`${localName} = {`);
  assert.notStrictEqual(start, -1, `${localName} not found — the Terraform source moved`);
  const body = source.slice(start + `${localName} = {`.length);
  const end = body.indexOf('\n  }');
  assert.notStrictEqual(end, -1, `could not find the end of ${localName}`);
  return body.slice(0, end);
}

describe('parity with alarm-sets.tf', () => {
  const tf = readTf('alarm-sets.tf');

  test('every class in _alarm_class_defaults exists in the generator', () => {
    const body = parseHclMapBlock(tf, '_alarm_class_defaults');
    const classes = [...body.matchAll(/^\s{4}(\w+)\s*=/gm)].map((m) => m[1]);

    assert.ok(classes.length >= 8, `expected the full class list, parsed: ${classes.join(', ')}`);
    for (const cls of classes) {
      assert.ok(
        Object.prototype.hasOwnProperty.call(CLASS_DEFAULTS, cls),
        `alarm-sets.tf has class '${cls}' but the generator does not — update CLASS_DEFAULTS in src/generate.js`
      );
    }
  });

  test('namespace and dimension agree for every class', () => {
    const body = parseHclMapBlock(tf, '_alarm_class_defaults');
    for (const m of body.matchAll(
      /^\s{4}(\w+)\s*=\s*\{\s*namespace\s*=\s*"([^"]+)",\s*dimension\s*=\s*"([^"]+)"\s*\}/gm
    )) {
      const [, cls, namespace, dimension] = m;
      assert.strictEqual(CLASS_DEFAULTS[cls].namespace, namespace, `namespace drift for ${cls}`);
      assert.strictEqual(CLASS_DEFAULTS[cls].dimension, dimension, `dimension drift for ${cls}`);
    }
  });

  test('the generator invents no classes the module lacks', () => {
    const body = parseHclMapBlock(tf, '_alarm_class_defaults');
    const classes = [...body.matchAll(/^\s{4}(\w+)\s*=/gm)].map((m) => m[1]);
    for (const cls of Object.keys(CLASS_DEFAULTS)) {
      assert.ok(classes.includes(cls), `generator has class '${cls}' that alarm-sets.tf does not`);
    }
  });

  test('the alarm-name convention is still "<group>-<metric>-<resource>"', () => {
    // If this key format changes in the module, the two appliers would create
    // duplicate alarms under different names rather than converging.
    assert.match(tf, /key\s*=\s*"\$\{group_name\}-\$\{metric\.name\}-\$\{resource_name\}"/);
  });
});

describe('parity with dashboard.tf', () => {
  const tf = readTf('dashboard.tf');

  test('every class in _dashboard_class_metrics exists in the generator', () => {
    const body = parseHclMapBlock(tf, '_dashboard_class_metrics');
    const classes = [...body.matchAll(/^\s{4}(\w+)\s*=/gm)].map((m) => m[1]);

    assert.ok(classes.length >= 8, `expected the full class list, parsed: ${classes.join(', ')}`);
    for (const cls of classes) {
      assert.ok(
        Object.prototype.hasOwnProperty.call(DASHBOARD_METRICS, cls),
        `dashboard.tf has class '${cls}' but the generator does not`
      );
    }
  });

  test('the charted metrics agree for every class', () => {
    const body = parseHclMapBlock(tf, '_dashboard_class_metrics');
    for (const m of body.matchAll(/^\s{4}(\w+)\s*=\s*\[([^\]]+)\]/gm)) {
      const [, cls, list] = m;
      const metrics = [...list.matchAll(/"([^"]+)"/g)].map((x) => x[1]);
      assert.deepStrictEqual(DASHBOARD_METRICS[cls], metrics, `metric drift for ${cls}`);
    }
  });
});

describe('parity with the extension registry', () => {
  test('the generator refuses exactly the extensions it cannot build', () => {
    // extensions.tf is the source of truth for what an extension IS. If a new
    // one is registered, this test fails until the generator either supports
    // it or explicitly refuses it.
    const tf = readTf('extensions.tf');
    const start = tf.indexOf('extension_registry = {');
    const registered = [...tf.slice(start, tf.indexOf('\n  }', start)).matchAll(/^\s{4}(\w+)\s*=\s*\{/gm)].map(
      (m) => m[1]
    );

    const supported = ['Alarms', 'Dashboard'];
    const refused = ['CustomDomain'];

    assert.deepStrictEqual(
      registered.sort(),
      [...supported, ...refused].sort(),
      'the extension registry changed — teach the generator to build or refuse the new extension'
    );
  });
});
