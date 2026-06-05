// CommonJS loader for the optional ts-node engine.
//
// Run by typescript-parser.js as:
//   node -r ts-node/register/transpile-only ts-config-loader.cjs <absolute-config-path>
//
// This path is used only when ts-node + typescript are installed in scripts/. It
// reproduces the historical ts-node behaviour — CommonJS execution, so module-scope
// `require()` works, and loose resolution, so extensionless relative imports
// (`from './types'`) resolve. The default (no-install) engine is the native one in
// ts-config-loader.mjs; this is the opt-in compatibility upgrade for legacy configs.

const path = require('path');

async function main() {
  const configPath = process.argv[2];
  if (!configPath) {
    console.error('ts-config-loader: missing config path argument');
    process.exit(1);
  }

  // ts-node/register has hooked require() to transpile .ts on load.
  const mod = require(path.resolve(configPath));

  let config = mod && mod.default !== undefined ? mod.default : mod;
  if (typeof config === 'function') config = await config();
  if (config && typeof config.then === 'function') config = await config;

  if (!config || typeof config !== 'object') {
    console.error('Configuration must export an object');
    process.exit(1);
  }

  process.stdout.write(JSON.stringify(config));
}

main().catch((error) => {
  console.error(error && error.stack ? error.stack : String(error));
  process.exit(1);
});
