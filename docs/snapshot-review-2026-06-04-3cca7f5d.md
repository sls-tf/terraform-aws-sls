# Point-in-Time Technical & Architectural Review — sls.tf

- **Snapshot taken:** 2026-06-04, commit `3cca7f5d46906fc99e695e8076e34c4c97800e92` (`3cca7f5d`), branch `main`
- **Scope reviewed:** the full repository as it stood at that commit — the Terraform module HCL (`*.tf`), the Node.js support scripts (`scripts/`), the schema-generation tool (`tools/schema-generator/`) and its committed output (`generated/`), the JSON schemas (`schemas/`), the Terraform test suite (`tests/`), CI/CD workflows (`.github/workflows/`), the documentation set (root design notes, `docs/`, `agent-os/`), and the Astro documentation website (`website/`).
- **Explicitly out of scope:** this document does not assess the module relative to other Terraform modules or alternatives (e.g. native SAM/CDK, the official Serverless Framework), the wider delivery or organisational context in which it is consumed, the downstream consumer repositories that pin it, or whether any other component or service was correct. It evaluates this repository, in isolation, at one commit.
- **Validity:** this is a snapshot. Every finding, score, and recommendation reflects the repository **only at commit `3cca7f5d` on 2026-06-04**. Subsequent commits may have changed any of it. It is a dated record, not a current or comparative verdict, and should be read as "what was true at that instant," not "what is true now." Regenerating this review against a later commit produces a separate artifact; this file is immutable.

---

## 0. What the repository was, at this commit

At `3cca7f5d`, the repository was a single pure-Terraform module that translated Serverless Framework (`serverless.yml` / `serverless.ts`) and AWS SAM (`template.yaml`) configurations into native AWS resources (Lambda, IAM, API Gateway, S3, DynamoDB, SQS, SNS, EventBridge, CloudFront/Lambda@Edge) without a separate build step. It was authored almost entirely by one person (39 of 42 commits by "Tom Redstone," the remainder by name variants of the same author and one bot commit). The first commit dated to 2025-10-26; the snapshot commit was the head on 2026-06-04. The module was at release tag `v0.3.11`, having shipped eleven `v0.3.x` tags. It was consumed in production by external repositories (referenced in tracked notes as the "texe" monorepo).

Around the module sat three secondary bodies of work: a Node.js layer (a 537-line CloudFormation-intrinsic evaluator powering SAM support, a TypeScript-config parser, and an "elemental"→Serverless converter); a well-tested schema-generation tool that produced committed Terraform validation files from versioned JSON schemas; and an independent Astro documentation site with its own deploy pipeline.

---

## 1. Architecture and structure

**Shape, as observed.** The module followed a single linear pipeline: **parse → resolve → translate → generate**. Configuration entered as YAML/JSON/TS or SAM, was parsed (SAM via an external Node process that fully evaluated intrinsics; TS via another external Node process; YAML via native `yamldecode`), normalised into one internal "SLS-like" config object, had `${self:}`/`${env:}` variables resolved, and was then consumed by resource files (`main.tf`, `custom_resources.tf`, `event_sources.tf`, `cloudfront_events.tf`, etc.) that emitted AWS resources. A single translation point (`sam-parser.tf`'s `sam_as_sls_config`) let SAM templates reuse the entire SLS resource-generation path unchanged — a deliberate and sound design choice that avoided a second parallel resource layer.

**Strengths visible at this commit.**
- **One internal representation.** Both SLS and SAM converged on the same config object, so resource generation was written once. This was the strongest architectural decision in the repository.
- **Plan-known-key discipline.** `for_each` keys for functions, custom resources, and HTTP events were derived from *structural* sets (`local._function_names`, built by iterating the raw template) rather than from value-contaminated resolved config (`locals.tf:205-212`). This kept keys known at plan time even when SAM parameters carried unknown values — a non-obvious correctness property that prior commits (per the git history) were specifically repaired to preserve.
- **Intrinsic evaluation pushed into Node.** Rather than attempting CloudFormation `!If`/`!Sub`/`!FindInMap` evaluation in HCL, the work was done in `scripts/sam-preprocessor.js` and handed back as plain JSON. This was the right boundary; the alternative (HCL-side evaluation) had previously shipped and failed (documented in `report.md`).

**Weaknesses visible at this commit.**
- **Concentration in `locals.tf` (1,035 lines).** The parse/validate/resolve/event-extraction/IAM-merge logic was almost entirely in one file, much of it as deeply nested single expressions. This was the dominant structural risk (see §2, §4).
- **Hardcoded breadth limits.** API Gateway path nesting was unrolled to a fixed depth of 4 (`main.tf`, `depth_1`…`depth_4`); `${env:}` resolution ran a fixed three passes (`variable_resolution.tf:301-339`); `${self:}` resolution covered an enumerated set of paths rather than arbitrary nesting. These were correct within their bounds but silently incomplete beyond them.
- **Two external-process dependencies at plan time.** SAM and TS parsing shelled out to Node via `data.external`, with `npm install` triggered inline on first run (`sam-parser.tf:18-21`). This coupled `terraform plan` to a working Node toolchain and network access, outside Terraform's normal model.

---

## 2. Code quality

**General character.** The HCL was idiomatic and unusually heavily commented for Terraform — many of the hardest expressions carried multi-line rationale explaining *why* a particular form was used (e.g. the type-unification notes around `archive_file`, the heterogeneous-policy-list note at `sam-parser.tf:298-304`). Comment quality, where present, was a genuine asset and reflected hard-won knowledge of Terraform's type system.

**Recurring quality signals, at this commit.**
- **Defensive `try()` density.** `try()` wrapped a large fraction of expressions to absorb missing keys and type mismatches. In the parsing layer this was appropriate, but the same idiom also silently swallowed *real* errors: e.g. nested `try(length(var.lambda_code_source.bucket), 0)` in a validation (`variables.tf:102`) would mask a null bucket, and policy statements whose `Resource` resolved empty were dropped without signal (`sam-parser.tf:311-322`). The line between "tolerate optional config" and "hide a bug" was crossed in several places.
- **Monolithic expressions.** The validation-error aggregation (`locals.tf:37-85`) concatenated eight-plus independent error lists into one expression; the S3 artefact-name derivation (`locals.tf` ~297-316) split, filtered, and indexed a path twice within one expression and had no guard against an empty result. These were correct for current inputs but brittle to modify.
- **Dead and duplicated code.**
  - A size-validation "approaching limit" precondition was a tautology — `output_size <= 41943040 || output_size > 41943040` (`main.tf:92-94`) is always true, so the warning message was unreachable. The intended >40 MB warning never fired.
  - `variable_resolution.tf.backup` (a 19 KB stale copy of `variable_resolution.tf`) was tracked in git, as were `converted-user-service.yml` and `converted-user-service-fixed.yml` (iteration artifacts). These polluted history and blame and created ambiguity about the authoritative source.
- **Deprecated provider usage.** `data.aws_region.current.name` (`sam-parser.tf:26`) was deprecated under the AWS provider v6 line that the module *required* (`versions.tf` pinned `aws >= 6.0`); `terraform validate` emitted a deprecation warning at this commit. CloudFront generation used the deprecated `forwarded_values` block (`custom_resources.tf` ~309-353) rather than cache policies.

**Node layer.** `sam-preprocessor.js` was logically sound and well structured (intrinsic dispatch, `AWS::NoValue` sentinel, condition resolution, per-resource attribute synthesis for `!GetAtt`) but carried **no unit tests** despite being mission-critical. `typescript-parser.js` constructed TypeScript source by string-interpolating file paths into a generated script (`~lines 103, 108`), escaping backslashes but not quotes/backticks — a code-injection-shaped hazard for adversarial paths, and untested. The `tools/schema-generator/` tool stood in contrast: a 59-test Jest suite, clean separation (loader/extractor/generator/templates), and Handlebars-templated output.

---

## 3. Database and migration design

The module had **no database and no schema migrations** in the conventional sense; it was infrastructure-as-code, not a stateful application. The closest analog at this commit was the **schema-generation and validation pipeline**, which is assessed here in that spirit.

- **Source of truth.** `schemas/serverless-framework/{v2.x,v3.x,v4.x}.json` held versioned JSON Schemas for the Serverless Framework config formats. `tools/schema-generator/` transformed these into `generated/validation-{common,v2,v3,v4}.tf`, which were **committed** to the repository and consumed as the module's config validation.
- **"Migration" analog — version drift.** The equivalent of migration risk here was *generated-code drift*: the committed `generated/*.tf` could fall out of sync with the source schemas or the generator. This was mitigated by `.github/workflows/validate-generated-code.yml`, which regenerated and compared SHA-256 checksums and failed on drift, plus a runtime-budget check. This was a credible control. Residual risk: the schemas themselves carried **no provenance metadata** (no record of which upstream Serverless release/tag or fetch date each JSON corresponded to), so "is this schema current?" could not be answered from the repository alone. A weekly `schema-update.yml` job fetched upstream schemas and opened PRs, partially addressing freshness.
- **Multi-version handling.** v2/v3/v4 were handled side-by-side (Draft-04 for v2, Draft-07 for v3/v4) rather than via an evolving single schema — appropriate for a tool that must accept all three.

Net: for a module with no datastore, the schema pipeline was the best-engineered subsystem in the repository and the one with the strongest automated guardrails.

---

## 4. Team maintainability and bus-factor risk

- **Bus factor of one.** At this commit, effectively all knowledge resided with a single author. The most intricate code (the `locals.tf` resolution engine, the intrinsic evaluator, the plan-known-key invariants) was exactly the code least amenable to being picked up cold. The dense rationale comments reduced this risk but did not eliminate it; several invariants ("iterate `_function_names` not the resolved map," "this `for` must not use a ternary because of type unification") lived in comments rather than in tests that would fail if violated.
- **Concentration risk.** `locals.tf` at 1,035 lines was the single point most likely to be edited and most likely to break in non-obvious ways. The repository's own git history at this commit showed a cluster of recent commits fixing type-unification and key-stability regressions in this area — evidence that the file was both actively churned and easy to get subtly wrong.
- **Stale internal documentation.** `tests/TEST_COVERAGE.md` and `tests/LAMBDA_COVERAGE.md` both asserted "28 tests (100% passing)" while the suite actually contained 49 test files / ~267 `run` blocks / ~569 assertions. A reader trusting these docs would materially misjudge both the size and the health of the suite.
- **Cognitive load from `agent-os/`.** Roughly 70 of the repository's ~101 tracked markdown files lived under `agent-os/` (product specs, standards, roadmap for AI-assisted development). These did not affect module behaviour but substantially inflated the surface a newcomer had to triage to find authoritative material.
- **Repository hygiene.** Tracked backup/iteration files (above) and an untracked 3.9 MB `texe-vendored-fork/` working copy on disk (a deliberate demonstration of consumer-side workarounds, since integrated) added noise. Neither was load-bearing at this commit.

---

## 5. Delivery risk (prioritised)

1. **(High) The test suite could not execute under the module's own declared provider constraint.** `versions.tf` required `aws >= 6.0` (lock at v6.42.0). AWS provider v6 rejected the `dynamic "endpoints"` block used inside `provider "aws"` in **17 of 49 test files** ("Blocks of type dynamic are not expected here"). The primary CI test workflow (`.github/workflows/test.yml`) ran `terraform test -var="use_localstack=…"`, so it would fail on those files. The module therefore had no working automated correctness gate at this commit for the bulk of its behaviour. This is the central delivery risk: changes could not be validated end-to-end by the suite as written.
2. **(High) CI gave false confidence.** A second workflow (`module-tests.yml`) ran only `fmt`/`validate`/`plan` against a few fixtures — these passed and would read as "green," masking that `terraform test` itself was broken. The split between a passing lightweight workflow and a failing full-test workflow made suite health easy to misread.
3. **(Medium) 27 of 49 test files declared no provider** (`provider "aws"` or `mock_provider`). Pure-logic plan tests that touch any AWS data source/resource fail with "provider requires explicit configuration" absent a configured provider; these relied on environment specifics (LocalStack/credentials) rather than being hermetic.
4. **(Medium) Plan-time coupling to Node + network.** SAM/TS paths shelled to Node and could trigger `npm install` during `plan`; a plan in a Node-less or network-restricted environment would fail outside Terraform's normal error surface.
5. **(Medium) Supply-chain pinning gaps in CI.** `aquasecurity/trivy-action@master` was referenced unpinned in two workflows; the Terraform version in the test workflow was loosely constrained.
6. **(Low) Stale coverage docs and tracked dead files** (delivery-adjacent: they erode trust and slow review rather than break builds).

---

## Correctness bugs identified, with production impact

Each item below was verified against the source at `3cca7f5d`.

1. **API Gateway method/integration `for_each` key omitted the path.** `main.tf:343` (and the matching integration block) keyed by `"${event.function_name}_${lower(event.http_method)}"`. Two HTTP events on the *same function and method but different paths* (e.g. `GET /users` and `GET /users/{id}` handled by one function — a valid Serverless configuration) produce duplicate keys. **Impact:** `terraform plan` fails with a duplicate-key error ("Two different items produced the key…"), blocking an otherwise legal config; the key cannot be disambiguated without including the path. Severity: high (blocks valid input).

2. **Size-validation "approaching limit" warning was unreachable.** `main.tf:92-94` used `output_size <= 41943040 || output_size > 41943040`, always true, so the precondition never failed and the >40 MB warning never surfaced. **Impact:** operators received no early signal before crossing the 50 MB hard limit; the failure then appeared only at the hard-limit precondition or at apply. Severity: low (lost warning, not a wrong deployment).

3. **Conditionally-gated IAM policy statements could be silently dropped.** `sam-parser.tf:311-322` filtered out statements whose `Resource` list resolved empty (e.g. an `!If` branch resolving to `AWS::NoValue`). **Impact:** a statement intended to be present under some conditions could vanish with no error, leaving a function under-permissioned at runtime (a failure that surfaces only when the code path needing the permission executes). Severity: medium.

4. **Deprecated provider attribute under a required-major provider.** `data.aws_region.current.name` (`sam-parser.tf:26`) was deprecated in AWS provider v6, which `versions.tf` mandated. **Impact:** a deprecation warning at this commit; a likely hard break on a future provider minor/major that removes the attribute, affecting every SAM plan (the only path that reads it). Severity: medium (time-bomb).

5. **`${env:}` resolution bounded to three references per value; `${self:}` to an enumerated path set.** `variable_resolution.tf:301-339`. **Impact:** a config value containing four or more `${env:}` references, or a `${self:}` reference to a non-enumerated nested path, resolves only partially and the literal `${…}` survives into generated resources. With `strict_variable_resolution` off, this is silent; the strict check only inspected top-level keys, so nested unresolved references could pass even in strict mode. Severity: medium (silent wrong value in generated infra).

6. **CloudFront used deprecated `forwarded_values`.** `custom_resources.tf` (~309-353). **Impact:** distributions generated with a structure AWS has deprecated in favour of cache policies; functional at this commit but on a deprecation path. Severity: medium (forward risk).

Lower-confidence items flagged for verification rather than asserted as bugs: FIFO-queue detection keyed on an `.fifo` ARN suffix (`locals.tf` ~707) would not recognise SAM `!Ref` logical IDs and could apply standard-queue batch-size validation to a FIFO queue; "same path pattern, multiple behaviours" in Lambda@Edge merging may keep only the first behaviour. These were consistent with the code read but not exercised against a failing fixture at review time.

### Addendum (verification done immediately after this snapshot, same commit `3cca7f5d`)

Two further correctness bugs were confirmed by planning SAM templates to completion under Terraform 1.14.8 — a path the original analysis above did not exercise (it relied on `terraform validate`, which type-checks but does not fully evaluate `locals`). Both were present at `3cca7f5d` and are recorded here for completeness of the same-commit record:

7. **The entire SAM path failed at plan time with "Inconsistent conditional result types."** In `locals.tf`'s `parsed_config`, the unused `yamldecode(file_content)` ternary branch inferred a concrete object type from the static SAM file (`AWSTemplateFormatVersion`/`Transform`/`Resources`) that could not structurally unify with the translated `sam_as_sls_config` object. **Impact:** every SAM configuration errored before any resource was planned, under the Terraform version in use at review. This did not surface earlier precisely because the test suite could not run (Delivery risk §1) and because `terraform validate` does not evaluate the conditional. Severity: high (SAM unusable at this Terraform version). A second instance of the same class existed in `sam-parser.tf`'s `sam_resources_translated` (the `AWS::Serverless::SimpleTable` translation branch vs the pass-through `resource` branch), triggered by templates containing non-function resources or `Globals`.

This addendum strengthens, rather than revises, the strategic assessment: it is direct evidence that high-severity defects were being masked by the inability to run the suite, which is the report's central argument for prioritising test-harness repair (§5, fix list items 1–3). The "Confidence in correctness" score below was set with this class of risk already in mind.

---

## Strategic assessment

At this commit, the evidence favoured **(B) a targeted refactor and stabilisation pass**, not (A) unmodified continuation and not (C) rewrite.

- **Against (C) rewrite.** The hardest and most valuable parts were already solved and would simply have to be re-solved: the single-internal-representation design, the plan-known-key invariants, and the intrinsic evaluator represent real, non-obvious domain knowledge. A rewrite would discard that for no architectural gain — the architecture was not the problem.
- **Against (A) continue as-is.** The module had, at this commit, no working full-suite correctness gate (the provider/test-harness inconsistency) while carrying concentrated complexity in one churned file and several latent correctness bugs. Continuing to add features on top of an unrunnable test suite compounds risk; each change is unvalidated.
- **For (B) refactor/stabilise.** The high-leverage work was bounded and mostly mechanical-to-moderate: reconcile the provider constraint with the test harness (migrate the 17 `dynamic "endpoints"` blocks to a v6-compatible form or `mock_provider`, and give the 27 provider-less files a hermetic provider), decompose `locals.tf` along its natural seams (parse / validate / resolve / events / IAM), fix the enumerated correctness bugs, and refresh the coverage docs. None of this required re-architecting.

**Tradeoffs.** (B) front-loads unglamorous test-infrastructure and decomposition work before the next feature. The cost of deferring it was that the bus-factor-of-one author remained the only safe editor of the most critical file, and that the suite could not catch regressions — the exact conditions under which the recent type-unification/key-stability regressions (visible in the history) had occurred and been hand-fixed.

---

## Prioritised fix list (ordered)

**Immediate (restore the ability to validate changes):**
1. Reconcile `versions.tf`'s `aws >= 6.0` with the test harness: replace the `dynamic "endpoints"` provider blocks in the 17 affected test files with a v6-compatible provider configuration (or `mock_provider "aws"` for pure-logic tests), so `terraform test` runs at all.
2. Give the 27 provider-less test files a configured or mocked provider so they are hermetic and do not depend on ambient credentials/LocalStack.
3. Make CI honest: ensure a workflow actually runs the full `terraform test` and gates merges on it; stop treating the `fmt/validate/plan`-only workflow as proof of test health.

**Before next release:**
4. Fix the API Gateway `for_each` key to include the path (`main.tf:343` and the integration block), unblocking same-function/same-method/different-path configs.
5. Replace `data.aws_region.current.name` with the v6-current form; migrate CloudFront `forwarded_values` toward cache policies (or document the deprecation explicitly).
6. Repair or remove the tautological size-validation warning (`main.tf:92-94`); decide whether an emitted warning is achievable in HCL and either implement it correctly or delete the dead precondition.
7. Make `strict_variable_resolution` inspect nested values, and either lift the fixed `${env:}` pass count / `${self:}` path enumeration or document the bounds as hard limits with a validation error when exceeded.
8. Add unit tests for `scripts/sam-preprocessor.js` (the untested 537-line evaluator) and harden `scripts/typescript-parser.js` path interpolation against quote/backtick injection.
9. Refresh `tests/TEST_COVERAGE.md` / `LAMBDA_COVERAGE.md` to the real counts and status; remove tracked backup/iteration files (`variable_resolution.tf.backup`, `converted-user-service*.yml`).

**Longer-term (reduce bus-factor and concentration risk):**
10. Decompose `locals.tf` (1,035 lines) into focused files along its pipeline seams, and convert the load-bearing invariants currently expressed only in comments (plan-known keys, no-ternary-for-type-unification, heterogeneous policy iteration) into tests that fail when violated.
11. Pin CI actions (`trivy-action@master` → a version) and the Terraform version in the test workflow.
12. Add provenance metadata to `schemas/` (upstream version/tag and fetch date) so schema currency is answerable from the repository.
13. Reconsider whether `agent-os/` (~70 docs) belongs in this repository or a separate space, to lower onboarding surface.

---

## Final verdict (scored as of commit `3cca7f5d`, 2026-06-04; out of 10)

- **Confidence in correctness — 5/10.** *Core pipeline thoughtfully defended, but several latent bugs and no runnable full-suite gate at this commit to catch them.*
- **Maintainability — 5/10.** *Strong rationale comments offset by a 1,035-line hotspot, dead/backup files, and invariants held in prose rather than tests.*
- **Scalability (feature and config growth) — 5/10.** *Clean single-representation core, but hardcoded depth/pass/path limits cap growth silently rather than loudly.*
- **Onboarding — 4/10.** *Good local comments undercut by stale coverage docs, a bus-factor of one over the hardest code, and ~70 ancillary `agent-os/` documents to wade through.*
- **Production readiness — 5/10.** *Already generating real infrastructure for live consumers, yet shipping with an unrunnable test suite under its own declared provider and known correctness gaps.*

These scores describe the repository at one instant. They are not a judgement of the author or of the module's trajectory, and they should not be read as current once any of the listed fixes have landed.
