# Extension config schemas — scoped, deferred

**Status:** deferred (may never be built)
**Parent:** [EXTENSIONS.md](EXTENSIONS.md)

The extensions proposal describes the cost of adding an extension as "a registry
entry plus a schema". The registry entry is real and cheap. The schema half does
not exist and is not cheap. This file records what building it would involve, so
the parent doc can stop implying it is already available.

## What exists today

- `schemas/serverless-framework/v{2,3,4}.json` — vendored JSON Schemas for
  Serverless Framework configs.
- `tools/schema-generator/` — a Node tool that reads those schemas and emits
  `generated/validation-v{2,3,4}.tf`, each defining a
  `local.v{N}_validation_errors` list.
- **Nothing consumes them.** `v3_validation_errors` and its siblings are
  referenced by no `.tf` file in the module. The generated validation is dead
  code, and has been since it was generated (2025-10-28).

So the project does not have working schema-driven validation to extend. It has
a prototype of one, unwired.

## What a schema layer for extensions would require

1. **Wire up what's already generated.** Decide whether the SF-config validators
   are wanted at all, fix whatever kept them from being wired (their accuracy is
   unverified — e.g. `validation-v3.tf` checks
   `local.parsed_config.functions.handler`, which reads a field off the
   functions *map* rather than each function, so it can never fire correctly),
   and route them into `local.validation_errors`. Doing this for extensions
   while leaving the SF validators dead would mean two schema paths, one of them
   abandoned.

2. **Author schemas for the three extensions.** `Alarms` is the awkward one: its
   shape is `defaults` + `groups.<class>` where the permitted keys of a group
   depend on the class (auto-enumerating classes vs `api_gateway`, which
   requires explicit `resource_names`). That is a `dependentSchemas`/`if-then`
   construct, not a flat property list.

3. **Extend the generator to emit extension validators.** The current generator
   handles required fields, enums, and type checks against a fixed config root.
   Extension config is read through two different parses (structural for
   `Alarms`/`Dashboard`, resolved for `CustomDomain`) and arrives via a
   `jsondecode(jsonencode(...))` launder, so the generated expressions would
   need a configurable root and parse selection.

4. **Handle the constructs HCL can't express well.** Conditional subschemas,
   `oneOf`, and pattern properties all degrade badly into `try()`/`can()`
   expression trees. Expect the generated file to be large and hard to read
   relative to the errors it catches.

5. **Keep it in sync.** Every extension change touches the schema, the generated
   file, and the implementation. The generated file is checked in, so a
   contributor who edits an extension without running `npm run generate:*`
   ships a stale validator.

Rough size: the generator work is the bulk of it, and it is a Node project with
its own test suite (`tools/schema-generator/tests/`) rather than a Terraform
change. Not a sitting afternoon.

## What we do instead

Hand-written validation in the extension's own `.tf` file, appended to
`local.validation_errors` — the same pattern as `sam-validation.tf`,
`iam_validation_errors`, `event_source_validation_errors`, and every other
validation in the module. It is the established idiom, it produces better
messages than a schema path emits, and it costs a few lines per rule.

The registry (see [EXTENSIONS.md](EXTENSIONS.md) §2) therefore carries a
reference to the extension's validation local, not to a schema file.

## When to revisit

Reconsider if all three hold:

- The generated SF-config validators get wired in and prove useful, so there is
  one working schema path rather than a second speculative one.
- The extension count passes roughly six, where hand-written validation starts
  to duplicate itself noticeably.
- Something external wants the schemas as data — editor completion for
  `Metadata.SlsTf.*`, or generated reference docs on the website.

Until then this stays a paragraph in a deferred doc, and "cheap to add" means a
registry entry plus a handful of validation lines.
