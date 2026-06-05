// Loads a Serverless TypeScript config and prints it as JSON on stdout.
//
// Run by typescript-parser.js as:
//   node --experimental-transform-types --disable-warning=ExperimentalWarning \
//        ts-config-loader.mjs <absolute-config-path>
//
// The --experimental-transform-types flag makes Node execute TypeScript directly
// (type annotations erased; enums/namespaces/parameter-properties transformed), so
// NO ts-node / typescript / npm install is required — only Node >= 22.7. The config
// path is passed as argv (never interpolated into source), so there is no temp file
// and no code-injection surface.

import { pathToFileURL } from 'node:url';

async function main() {
  const configPath = process.argv[2];
  if (!configPath) {
    console.error('ts-config-loader: missing config path argument');
    process.exit(1);
  }

  // import() resolves the user's .ts (and any .ts it imports); pathToFileURL keeps
  // absolute paths valid as ESM specifiers on every platform, Windows included.
  const mod = await import(pathToFileURL(configPath).href);

  let config = mod.default ?? mod;
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
