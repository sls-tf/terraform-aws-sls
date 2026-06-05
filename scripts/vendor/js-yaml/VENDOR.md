# Vendored js-yaml (tree-shaken)

`js-yaml.cjs` is a committed, tree-shaken build of [js-yaml](https://github.com/nodeca/js-yaml),
bundled down to the three symbols `scripts/sam-preprocessor.js` uses: `load`,
`Type`, and `DEFAULT_SCHEMA`. The dumper and all other exports are tree-shaken
away.

It is committed so that running `terraform plan` against a SAM template
(`config_format = "sam"`) is **self-contained**: the only runtime requirement is
`node` on PATH. No `node_modules`, no `npm install`, no network access. This is
the common path for module consumers; only the optional TypeScript-config path
(`config_format = "typescript"`) still needs `npm install` in `scripts/` (for
`ts-node` + `typescript`), and it fails loud with instructions if they are
missing.

## Provenance

| | |
|---|---|
| Package | `js-yaml` |
| Version | `4.1.0` |
| License | MIT (see `LICENSE` in this directory; also inlined in the bundle) |
| Bundler | `esbuild@0.28.0` (`--bundle --format=cjs --platform=node --target=node14 --minify --legal-comments=inline`) |
| Entry | `export { load, Type, DEFAULT_SCHEMA } from 'js-yaml'` |
| Output | `js-yaml.cjs` (~40 KB) |
| sha256 | `e0bca54ef1a007bed5fac1e5c69b0d3ab91917db943391ec8f009f3ec15e1f94` |

(The sha256 is esbuild-version-specific; it is recorded for drift detection, not
as a security guarantee. `revendor.sh` pins both versions so a clean rebuild
reproduces the same artifact.)

## How to re-vendor / upgrade

```sh
scripts/vendor/js-yaml/revendor.sh
```

This installs the pinned js-yaml + esbuild in a temp dir, rebuilds `js-yaml.cjs`
and refreshes `LICENSE`, and prints the new sha256. To upgrade js-yaml, bump
`JS_YAML_VERSION` in `revendor.sh`, run it, update the table above with the new
sha256, and commit `js-yaml.cjs`, `LICENSE`, and this file together.

## Why vendor instead of depend

`js-yaml` is a thin-surface, high-necessity, low-footprint dependency: the SAM
preprocessor calls 3 of its ~12 public symbols, but those three (custom-tag
`Type` registration + `DEFAULT_SCHEMA.extend` + `load`) are exactly what lets
CloudFormation intrinsics (`!Ref`/`!Sub`/`!If`/…) parse at all, and the whole
bundle is ~40 KB with no transitive dependencies. Committing it removes the
plan-time `npm install` side effect entirely for SAM consumers.
