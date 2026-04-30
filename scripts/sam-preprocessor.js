#!/usr/bin/env node
'use strict';

// SAM YAML preprocessor for sls.tf
//
// Terraform's yamldecode() raises an error on CloudFormation intrinsic function
// tags (!Ref, !Sub, !If, etc.) instead of stripping them.  This script uses
// js-yaml with a custom schema that treats those tags as transparent wrappers,
// returning the underlying scalar / sequence / mapping unchanged — the same
// behaviour the sam-parser.tf code expects.
//
// Protocol: Terraform external data source (JSON on stdin → JSON on stdout).

const yaml = require('js-yaml');
const fs   = require('fs');

const CFN_TAGS = [
  'Ref', 'Sub', 'If', 'And', 'Or', 'Not', 'Equals', 'Select',
  'Split', 'Join', 'FindInMap', 'GetAtt', 'GetAZs', 'ImportValue',
  'Base64', 'Cidr', 'Condition', 'Transform',
];

const types = CFN_TAGS.flatMap(tag =>
  ['scalar', 'sequence', 'mapping'].map(kind =>
    new yaml.Type(`!${tag}`, { kind, construct: d => d })
  )
);

const CFN_SCHEMA = yaml.DEFAULT_SCHEMA.extend(types);

let input = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', chunk => { input += chunk; });
process.stdin.on('end', () => {
  try {
    const { config_path } = JSON.parse(input || '{}');

    if (!config_path || !fs.existsSync(config_path)) {
      process.stdout.write(JSON.stringify({ content: '', error: `File not found: ${config_path || '(empty)'}` }));
      return;
    }

    const raw    = fs.readFileSync(config_path, 'utf8');
    const parsed = yaml.load(raw, { schema: CFN_SCHEMA });

    process.stdout.write(JSON.stringify({ content: JSON.stringify(parsed), error: '' }));
  } catch (e) {
    process.stdout.write(JSON.stringify({ content: '', error: e.message }));
  }
});
