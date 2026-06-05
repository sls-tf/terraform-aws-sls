#!/usr/bin/env node

/**
 * TypeScript Configuration Parser for sls.tf
 *
 * Parses Serverless Framework TypeScript configuration files (serverless.ts) and
 * converts them to JSON for Terraform consumption.
 *
 * Two engines, auto-selected, both dependency-light:
 *
 *   1. Native (default, zero install): Node's built-in TypeScript support
 *      (`--experimental-transform-types`, Node >= 22.7) executes the config
 *      directly. No ts-node, no typescript package, no `npm install` — just
 *      `node` on PATH. Handles standard, self-contained serverless.ts files.
 *
 *   2. ts-node (optional): used only when ts-node + typescript are installed in
 *      scripts/. Adds CommonJS execution and loose module resolution, so configs
 *      that use module-scope `require()`, extensionless relative imports, or
 *      tsconfig path aliases keep working. Opt in with `npm install` in scripts/.
 *
 * Either way the config path is handed to a committed loader as an argument, so
 * there is no generated temp script and no string-interpolation/code-injection
 * surface (unlike the previous temp-.ts approach).
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

// Absolute path to ts-node's transpile-only register hook, or null if ts-node +
// typescript are not installed in scripts/. Resolved to an absolute path (via the
// package location, avoiding subpath-exports quirks) so the child node — which
// runs in the user's working dir, not scripts/ — can `-r` it regardless of CWD.
function tsNodeRegisterPath() {
  try {
    require.resolve('typescript');
    const pkg = require.resolve('ts-node/package.json');
    const register = path.join(path.dirname(pkg), 'register', 'transpile-only.js');
    return fs.existsSync(register) ? register : null;
  } catch {
    return null;
  }
}

// Choose how to execute the user's config. Returns the argv for a child `node`,
// or an object with .reason set when neither engine is available.
function selectEngine(configPath) {
  const tsNodeRegister = tsNodeRegisterPath();
  if (tsNodeRegister) {
    return {
      kind: 'ts-node',
      args: ['-r', tsNodeRegister, path.join(__dirname, 'ts-config-loader.cjs'), configPath],
      // Hermetic ts-node: ignore any project tsconfig.json (which may set options
      // like module=NodeNext that conflict in transpile-only mode) and pin the
      // classic CommonJS options that make `require()`, extensionless relative
      // imports, and JSON imports work — the behaviour this engine exists to provide.
      env: {
        ...process.env,
        TS_NODE_TRANSPILE_ONLY: 'true',
        TS_NODE_SKIP_PROJECT: 'true',
        TS_NODE_COMPILER_OPTIONS: JSON.stringify({
          module: 'commonjs',
          moduleResolution: 'node',
          esModuleInterop: true,
          resolveJsonModule: true,
          allowJs: true,
          target: 'ES2020'
        })
      }
    };
  }
  if (nodeSupportsTypeScript()) {
    return {
      kind: 'native',
      args: ['--experimental-transform-types', '--disable-warning=ExperimentalWarning', path.join(__dirname, 'ts-config-loader.mjs'), configPath]
    };
  }
  return {
    reason: `TypeScript config files need either Node >= ${MIN_NODE.join('.')} (native, no install) ` +
      `or ts-node + typescript installed in the scripts directory; detected Node ${process.versions.node} ` +
      `with ts-node not installed. Upgrade Node, run \`npm install ts-node typescript\` in scripts/, or use serverless.yml.`
  };
}

// When the native engine fails to resolve a module or hits a CommonJS-ism, the
// config likely relies on ts-node conventions. Point the user at the opt-in engine.
function nativeFallbackHint(stderr) {
  return /ERR_MODULE_NOT_FOUND|require is not defined|Cannot use import statement|ERR_REQUIRE_ESM/.test(stderr || '')
    ? ' This config appears to use CommonJS `require()`, extensionless imports, or path aliases. ' +
      'Run `npm install ts-node typescript` in the scripts directory to enable the ts-node compatibility engine.'
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

    // Pick the execution engine (ts-node if installed, else native Node). Flags
    // go on the child (not this parent) so an unsupported-environment message is
    // emitted cleanly instead of Node rejecting a flag with a cryptic "bad option".
    const engine = selectEngine(resolvedConfigPath);
    if (engine.reason) {
      throw new Error(engine.reason);
    }

    const result = spawnSync(
      process.execPath,
      engine.args,
      { cwd: resolvedWorkingDir, encoding: 'utf8', timeout: 30000, stdio: ['ignore', 'pipe', 'pipe'], env: engine.env || process.env }
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

module.exports = { main, validateServerlessConfig, nodeSupportsTypeScript, tsNodeRegisterPath, selectEngine };
