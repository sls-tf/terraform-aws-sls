#!/usr/bin/env bash
#
# Re-vendors the tree-shaken js-yaml bundle used by scripts/sam-preprocessor.js.
#
# The SAM path needs only three js-yaml symbols (load, Type, DEFAULT_SCHEMA). This
# script builds a minimal CommonJS bundle containing just those (esbuild drops the
# dumper and everything else), so `terraform plan` of a SAM template requires no
# node_modules / npm install — only `node` on PATH.
#
# Usage:  scripts/vendor/js-yaml/revendor.sh
# Pins both js-yaml and esbuild so the output is reproducible. Bump the versions
# below to upgrade, then commit the regenerated js-yaml.cjs + LICENSE and update
# VENDOR.md (the printed sha256).
#
set -euo pipefail

JS_YAML_VERSION="4.1.0"
ESBUILD_VERSION="0.28.0"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cd "$TMP"
npm init -y >/dev/null 2>&1
npm install --silent "js-yaml@${JS_YAML_VERSION}" "esbuild@${ESBUILD_VERSION}" >/dev/null 2>&1

# Entry re-exports ONLY the symbols sam-preprocessor.js consumes. Anything else in
# js-yaml (notably the dumper) is tree-shaken away.
printf "export { load, Type, DEFAULT_SCHEMA } from 'js-yaml';\n" > entry.mjs

npx --no-install esbuild entry.mjs \
  --bundle --format=cjs --platform=node --target=node14 \
  --minify --legal-comments=inline \
  --outfile="${HERE}/js-yaml.cjs"

cp node_modules/js-yaml/LICENSE "${HERE}/LICENSE"

echo "Re-vendored js-yaml@${JS_YAML_VERSION} via esbuild@${ESBUILD_VERSION}"
echo "  $(cd "${HERE}" && sha256sum js-yaml.cjs)"
echo "Update VENDOR.md with the sha256 above if it changed, then commit js-yaml.cjs + LICENSE."
