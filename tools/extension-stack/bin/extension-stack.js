#!/usr/bin/env node
'use strict';

/**
 * extension-stack — turn an sls.tf extension sidecar into a companion
 * CloudFormation template, so a SAM deploy can be COMPLETED rather than
 * silently missing every extension.
 *
 *   node tools/extension-stack/bin/extension-stack.js \
 *     --template template.yaml --sidecar slstf.yaml --output extensions.json
 *
 *   sam deploy --template-file template.yaml   --stack-name my-svc
 *   aws cloudformation deploy --template-file extensions.json --stack-name my-svc-extensions
 *
 * Dependency-free by design, matching the module: YAML comes from the vendored
 * js-yaml already in scripts/vendor, and the output is JSON, which
 * CloudFormation accepts and which needs no serialiser.
 */

const fs = require('fs');
const path = require('path');

const yaml = require(path.join(__dirname, '../../../scripts/vendor/js-yaml/js-yaml.cjs'));
const { generate, GenerateError } = require('../src/generate');

const USAGE = `Usage: extension-stack --template <file> --sidecar <file> [--output <file>]

  --template, -t  SAM or CloudFormation template the extensions accompany
  --sidecar,  -s  sls.tf extension sidecar (conventionally slstf.yaml)
  --output,   -o  where to write the companion template (default: extensions.json)
                  "-" writes to stdout
  --help,     -h  this message
`;

function parseArgs(argv) {
  const args = { output: 'extensions.json' };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    const next = () => {
      const v = argv[++i];
      if (v === undefined) throw new GenerateError(`${arg} needs a value.`);
      return v;
    };
    switch (arg) {
      case '--template':
      case '-t':
        args.template = next();
        break;
      case '--sidecar':
      case '-s':
        args.sidecar = next();
        break;
      case '--output':
      case '-o':
        args.output = next();
        break;
      case '--help':
      case '-h':
        args.help = true;
        break;
      default:
        throw new GenerateError(`Unknown argument: ${arg}\n\n${USAGE}`);
    }
  }
  return args;
}

// SAM templates use CFN short tags (!Ref, !GetAtt, !Sub). Extensions live in
// plain YAML, but the TEMPLATE is read for its resource names, so the loader
// must tolerate them. Values are irrelevant here — only Type and the explicit
// name properties are read — so unknown tags collapse to a marker rather than
// failing the load.
const CFN_TAGS = ['Ref', 'GetAtt', 'Sub', 'Join', 'Select', 'Split', 'FindInMap', 'If', 'Equals', 'Not', 'And', 'Or', 'Base64', 'Cidr', 'ImportValue', 'GetAZs', 'Transform'];

const CFN_SCHEMA = yaml.DEFAULT_SCHEMA.extend(
  CFN_TAGS.flatMap((tag) =>
    ['scalar', 'sequence', 'mapping'].map(
      (kind) =>
        new yaml.Type(`!${tag}`, {
          kind,
          construct: (data) => ({ [`Fn::${tag}`]: data }),
        })
    )
  )
);

function loadYaml(file, { cfnTags = false } = {}) {
  if (!fs.existsSync(file)) throw new GenerateError(`File not found: ${file}`);
  const text = fs.readFileSync(file, 'utf8');
  return yaml.load(text, cfnTags ? { schema: CFN_SCHEMA } : undefined) || {};
}

function main(argv) {
  const args = parseArgs(argv);

  if (args.help) {
    process.stdout.write(USAGE);
    return 0;
  }
  if (!args.template || !args.sidecar) {
    process.stderr.write(`error: --template and --sidecar are both required.\n\n${USAGE}`);
    return 2;
  }

  const template = loadYaml(args.template, { cfnTags: true });
  const sidecar = loadYaml(args.sidecar);
  const stack = generate(template, sidecar);
  const json = `${JSON.stringify(stack, null, 2)}\n`;

  if (args.output === '-') {
    process.stdout.write(json);
  } else {
    fs.writeFileSync(args.output, json);
    const count = Object.keys(stack.Resources).length;
    process.stderr.write(
      `wrote ${args.output}: ${count} resource${count === 1 ? '' : 's'}.\n` +
        'Deploy it ALONGSIDE the SAM template — the template alone is an incomplete deploy.\n'
    );
  }
  return 0;
}

if (require.main === module) {
  try {
    process.exit(main(process.argv.slice(2)));
  } catch (err) {
    if (err instanceof GenerateError) {
      process.stderr.write(`error: ${err.message}\n`);
      process.exit(1);
    }
    throw err;
  }
}

module.exports = { main, parseArgs, loadYaml };
