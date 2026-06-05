#!/usr/bin/env node

/**
 * TypeScript Configuration Parser for sls.tf
 *
 * Parses Serverless Framework TypeScript configuration files (serverless.ts) and
 * converts them to JSON for Terraform consumption.
 *
 * Execution model — native by default, with an optional escape hatch:
 *
 *   - Native (default, zero dependencies): Node's built-in TypeScript support
 *     (`--experimental-transform-types`, Node >= 22.7) executes the config
 *     directly. No ts-node, no typescript package, no `npm install` — just
 *     `node` on PATH. Handles standard, self-contained serverless.ts files.
 *
 *   - Custom runner (opt-in): set the SLS_TF_TS_RUNNER env var to a TypeScript
 *     runner command — e.g. SLS_TF_TS_RUNNER="npx tsx" — for configs that need
 *     more than native type-stripping (module-scope `require()`, extensionless
 *     relative imports, tsconfig path aliases). That command runs the loader
 *     instead of `node`.
 *
 * Either way the config path is handed to a committed loader (ts-config-loader.mjs)
 * as an argument, so there is no generated temp script and no
 * string-interpolation/code-injection surface (unlike the previous temp-.ts approach).
 *
 * Invoked by typescript-parser.tf as `node typescript-parser.js`, with the query
 * (config_path, working_directory) delivered as JSON on stdin.
 */

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

// Minimum Node for --experimental-transform-types (native TS execution).
const MIN_NODE = [22, 7];

function nodeSupportsTypeScript() {
  const [major, minor] = process.versions.node.split('.').map(Number);
  return major > MIN_NODE[0] || (major === MIN_NODE[0] && minor >= MIN_NODE[1]);
}

// Choose how to execute the user's serverless.ts. Returns { kind, command, args }
// for a child process, or { reason } when no engine is available.
function selectEngine(configPath) {
  const loader = path.join(__dirname, 'ts-config-loader.mjs');

  // Escape hatch: an explicit TypeScript runner (e.g. "npx tsx") runs the loader.
  const custom = (process.env.SLS_TF_TS_RUNNER || '').trim();
  if (custom) {
    const [command, ...runnerArgs] = custom.split(/\s+/);
    return { kind: 'custom', command, args: [...runnerArgs, loader, configPath] };
  }

  if (nodeSupportsTypeScript()) {
    return {
      kind: 'native',
      command: process.execPath,
      args: ['--experimental-transform-types', '--disable-warning=ExperimentalWarning', loader, configPath]
    };
  }

  return {
    reason: `TypeScript config files require Node >= ${MIN_NODE.join('.')} for native execution; ` +
      `detected ${process.versions.node}. Upgrade Node, set SLS_TF_TS_RUNNER to a TypeScript runner ` +
      `(e.g. "npx tsx"), or use serverless.yml.`
  };
}

// When the native engine fails to resolve a module or hits a CommonJS-ism, the
// config needs more than native type-stripping. Point the user at the escape hatch.
function nativeFallbackHint(stderr) {
  return /ERR_MODULE_NOT_FOUND|require is not defined|Cannot use import statement|ERR_REQUIRE_ESM/.test(stderr || '')
    ? ' This config appears to use CommonJS `require()`, extensionless imports, or path aliases, which ' +
      `Node's native TypeScript support does not handle. Set SLS_TF_TS_RUNNER to a TypeScript runner that ` +
      'does — e.g. SLS_TF_TS_RUNNER="npx tsx" — and re-run.'
    : '';
}

function main() {
  let input;
  try {
    input = JSON.parse(fs.readFileSync(0, 'utf8'));
    const { config_path, working_directory = '.' } = input;

    if (!config_path) {
      throw new Error('config_path is required');
    }

    const resolvedWorkingDir = path.resolve(working_directory);
    const resolvedConfigPath = path.resolve(resolvedWorkingDir, config_path);

    if (!fs.existsSync(resolvedConfigPath)) {
      throw new Error(`Configuration file not found: ${resolvedConfigPath}`);
    }

    // Pick the execution engine (custom SLS_TF_TS_RUNNER if set, else native Node).
    // Flags go on the child (not this parent) so an unsupported-environment message
    // is emitted cleanly instead of Node rejecting a flag with a cryptic "bad option".
    const engine = selectEngine(resolvedConfigPath);
    if (engine.reason) {
      throw new Error(engine.reason);
    }

    const result = spawnSync(
      engine.command,
      engine.args,
      { cwd: resolvedWorkingDir, encoding: 'utf8', timeout: 30000, stdio: ['ignore', 'pipe', 'pipe'] }
    );

    if (result.error) {
      throw new Error(`Failed to execute TypeScript config: ${result.error.message}`);
    }
    if (result.status !== 0) {
      const stderr = (result.stderr || '').trim();
      const hint = engine.kind === 'native' ? nativeFallbackHint(stderr) : '';
      throw new Error(`TypeScript config execution failed: ${stderr || 'unknown error'}${hint}`);
    }

    let parsedConfig;
    try {
      parsedConfig = JSON.parse(result.stdout.trim());
    } catch (parseError) {
      throw new Error(`Failed to parse TypeScript output as JSON: ${parseError.message}. Output: ${result.stdout}`);
    }

    validateServerlessConfig(parsedConfig);

    console.log(JSON.stringify({
      status: 'success',
      config: JSON.stringify(parsedConfig),
      config_path: resolvedConfigPath
    }));

  } catch (error) {
    console.log(JSON.stringify({
      status: 'error',
      error: error.message,
      config_path: input ? input.config_path : 'unknown'
    }));
    process.exit(1);
  }
}

/**
 * Validate basic Serverless Framework configuration structure
 */
function validateServerlessConfig(config) {
  if (!config.service) {
    throw new Error('Missing required field: service');
  }

  if (!config.provider || !config.provider.name || config.provider.name !== 'aws') {
    throw new Error('Missing or invalid provider configuration. Provider name must be "aws".');
  }

  if (config.functions) {
    for (const [funcName, funcConfig] of Object.entries(config.functions)) {
      if (!funcConfig.handler) {
        throw new Error(`Function "${funcName}" missing required "handler" field`);
      }
    }
  }
}

if (require.main === module) {
  main();
}

module.exports = { main, validateServerlessConfig, nodeSupportsTypeScript, selectEngine };
