# Point-in-Time Technical & Architectural Review — sls.tf

- **Snapshot taken:** 2026-06-06, commit `f4f00dd1ca404d83b959f2f24d93b412e613e975` (`f4f00dd1`), branch `main`. The commit was authored 2026-06-05; the repository carried release tag `v0.3.15` at this commit (the 50th commit in the history).
- **Scope reviewed:** the full repository as it stood at that commit — the Terraform module HCL (`*.tf`), the Node.js support scripts (`scripts/`, including the vendored js-yaml bundle and the native-TypeScript loader), the schema-generation tool (`tools/schema-generator/`) and its committed output (`generated/`), the JSON schemas (`schemas/`), the Terraform test suite (`tests/`), CI/CD workflows (`.github/workflows/`), the documentation set (root design notes, `docs/`, `agent-os/`), the example configurations (`examples/`), and the Astro documentation website (`website/`). Where feasible, findings were exercised directly: `terraform fmt`, `terraform validate`, and selected `terraform test` runs were executed under Terraform v1.14.8 with `hashicorp/aws` v6.42.0.
- **Explicitly out of scope:** this document does not assess the module relative to other Terraform modules or alternatives (native SAM/CDK, the official Serverless Framework, Terraform-native Lambda modules), the wider delivery or organisational context in which it is consumed, the downstream consumer repositories that pin it, or whether any other component or service was correct. It evaluates this repository, in isolation, at one commit.
- **Validity:** this is a snapshot. Every finding, score, and recommendation reflects the repository **only at commit `f4f00dd1` on 2026-06-06**. Subsequent commits may have changed any of it. It is a dated record, not a current or comparative verdict, and should be read as "what was true at that instant," not "what is true now." Regenerating this review against a later commit produces a separate artifact; this file is immutable. A prior snapshot exists at `docs/snapshot-review-2026-06-04-3cca7f5d.md` (commit `3cca7f5d`, 2026-06-04); this document references that one only to record what changed in the intervening commits, not to supersede it.

---

## 0. What the repository was, at this commit

At `f4f00dd1`, the repository was a single pure-Terraform module that translated Serverless Framework (`serverless.yml` / `serverless.ts`) and AWS SAM (`template.yaml`) configurations into native AWS resources (Lambda, IAM, API Gateway REST, S3, DynamoDB, SQS, SNS, EventBridge, CloudFront/Lambda@Edge) without a separate build step. It was authored almost entirely by one person: 49 of 50 commits by "Tom Redstone" (across three unnormalised name spellings of the same identity), the remaining one by a bot. The first commit dated to 2025-10-26; the snapshot commit was the head on 2026-06-06 and carried release tag `v0.3.15`.

Around the module sat three secondary bodies of work, unchanged in shape from the prior snapshot: a Node.js layer (a 540-line CloudFormation-intrinsic evaluator powering SAM support, plus a TypeScript-config loader); a well-tested schema-generation tool that produced committed Terraform validation files from versioned JSON schemas; and an independent Astro documentation site with its own deploy pipeline.

**Net change since the prior snapshot (`3cca7f5d`, 2026-06-04).** The intervening commits were almost entirely corrective and were directed at the exact defects the prior snapshot enumerated. Confirmed at this commit:

- The two highest-severity correctness bugs from the prior record were fixed and each gained a hermetic regression test that passes: the API Gateway `for_each` key now includes the path (`main.tf:341`, `main.tf:358`; test `tests/api_gateway_method_keys.tftest.hcl`, 2 runs pass), and the SAM path's "Inconsistent conditional result types" failure was resolved by JSON-laundering the divergent branches in `parsed_config` (`locals.tf:22-27`) and `sam_resources_translated` (`sam-parser.tf:183-208`; test `tests/sam_plan_completes.tftest.hcl`, 2 runs pass).
- The tautological size-validation warning was removed; `main.tf:92-99` now carries only the real 50 MB hard-limit precondition.
- The deprecated `data.aws_region.current.name` was replaced with `.region` (`sam-parser.tf:27`).
- The TypeScript path was rebuilt to run `serverless.ts` on Node's native TypeScript support (Node ≥ 22.7) with an `SLS_TF_TS_RUNNER` escape hatch, dropping the required `ts-node`/`typescript` dependency. The prior code-injection-shaped hazard (file paths interpolated into generated TS source) was eliminated: the config path is now passed as a process argv to a committed loader (`scripts/ts-config-loader.mjs:24`), never interpolated into source. Regression test `tests/typescript_native_engine.tftest.hcl` passes.
- The SAM path's plan-time `npm install` was eliminated by committing a tree-shaken, provenance-documented js-yaml bundle (`scripts/vendor/js-yaml/`, with `VENDOR.md` recording version 4.1.0, MIT licence, build flags, and a SHA-256 that matches the committed artifact, plus a `revendor.sh` regeneration script).
- Sensitive `sam_template_parameters` are now prevented from tainting `for_each` iteration maps via `nonsensitive()` wrappers at the parse boundary (`locals.tf:25`, `locals.tf:38`) — the third issue recorded in the untracked `report.md` consumer bug report.
- Schema provenance was added at the README level (`schemas/serverless-framework/README.md`); the tracked `variable_resolution.tf.backup` was removed.

What did **not** change is the subject of the rest of this document. The single most consequential prior finding — that the test suite cannot execute as a full-suite correctness gate under the module's own toolchain — remained true at this commit, by a mechanism this snapshot confirmed directly (§5).

---

## 1. Architecture and structure

**Shape, as observed.** The module followed the same single linear pipeline observed at the prior snapshot: **parse → resolve → translate → generate**. Configuration entered as YAML/JSON/TS or SAM; was parsed (SAM via an external Node process that fully evaluated intrinsics, TS via a second external Node process, YAML via native `yamldecode`); was normalised into one internal "SLS-like" config object; had `${self:}`/`${env:}` variables resolved; and was consumed by resource files (`main.tf`, `custom_resources.tf`, `event_sources.tf`, `cloudfront_events.tf`, etc.) that emitted AWS resources. The single translation point (`sam-parser.tf`'s `sam_as_sls_config`) continued to let SAM templates reuse the entire SLS resource-generation path unchanged.

**Strengths visible at this commit.**
- **One internal representation.** Both SLS and SAM converged on the same config object, so resource generation was written once. This remained the strongest architectural decision in the repository.
- **Plan-known-key discipline, now defended at the type boundary.** `for_each` keys for functions, custom resources, and HTTP events were derived from *structural* sets rather than value-contaminated resolved config, and at this commit the parse boundary additionally stripped sensitivity (`nonsensitive()` at `locals.tf:25`, `locals.tf:38`) so that sensitive SAM parameter values could not propagate into iteration keys — a concrete hardening of an invariant the prior snapshot had identified as fragile.
- **Self-contained plan for the SAM path.** Pushing intrinsic evaluation into Node was the right boundary at the prior snapshot; at this commit the Node dependency was reduced to `node` on `PATH` plus a vendored library, removing the plan-time `npm install` and network requirement for SAM. This narrowed, but did not remove, the external-process coupling (the TS path still shells to Node).

**Weaknesses visible at this commit.**
- **Concentration in `locals.tf` (1,042 lines).** The parse/validate/resolve/event-extraction/IAM-merge logic remained almost entirely in one file, much of it as deeply nested single expressions. This was still the dominant structural risk and was marginally larger than at the prior snapshot.
- **Hardcoded breadth limits persisted.** API Gateway path nesting was still unrolled to a fixed depth of 4 (`main.tf`, `depth_1`…`depth_4`); `${env:}` resolution still ran a fixed three passes (`variable_resolution.tf:280-339`); `${self:}` resolution still covered an enumerated set of paths (`variable_resolution.tf:87-95`). These were correct within their bounds and silently incomplete beyond them.
- **A declared knob that did nothing.** `var.max_variable_depth` was declared, validated (1–50), and copied into `var_resolution_config.max_depth` (`variable_resolution.tf:33`), but the resolution engine never consumed it — the `${env:}` passes were hardcoded to three regardless. The similarly named `local.max_depth` (`locals.tf:566`) was an unrelated API-Gateway-tree value. A reader setting `max_variable_depth` would observe no behavioural change.
- **Two external-process dependencies remained at plan time.** SAM and TS parsing still shelled to Node via `data.external`. The SAM path was now offline-capable; the TS path required Node ≥ 22.7 (an experimental Node flag) or an explicit alternate runner, narrowing the environments in which a `terraform plan` over a `serverless.ts` succeeds out of the box.

---

## 2. Code quality

**General character.** The HCL remained idiomatic and unusually heavily commented, and at this commit several of the densest comments documented *fixes that had just landed* — e.g. the JSON-laundering rationale at `locals.tf:8-21` and `sam-parser.tf:178-182`, and the heterogeneous-policy-list note at `sam-parser.tf:308-316`. Comment quality, where present, remained a genuine asset and an accurate record of Terraform type-system hazards.

**Recurring quality signals, at this commit.**
- **Defensive `try()` density.** `try()` still wrapped a large fraction of expressions. In the parsing layer this remained appropriate; in places it continued to blur the line between tolerating optional config and hiding a bug. The IAM-statement filter at `sam-parser.tf:329-333` still dropped statements whose resolved `Resource` list was empty, without signal (see §6).
- **Fail-open behaviour in the intrinsic evaluator.** `scripts/sam-preprocessor.js` was logically sound and well structured, but resolved an unknown/typo'd CloudFormation condition to `true` by default (`scripts/sam-preprocessor.js:278`), so a resource gated on a misspelled condition would be *included* rather than rejected; `!Equals` stringified both operands (`scripts/sam-preprocessor.js:215`), so `true == "true"` compared equal. Neither is wrong for well-formed input; both fail toward inclusion rather than loud rejection.
- **`terraform fmt` was not clean.** `terraform fmt -check -recursive` exited non-zero at this commit, with six unformatted files: `custom_resources.tf`, `variables.tf`, `infrastructure/website/main.tf`, `tests/sam_cfn_intrinsics.tftest.hcl`, `tests/shared_test_config.tftest.hcl`, `tests/variable_infrastructure.tftest.hcl`. This is minor in itself but is load-bearing for CI (§5).
- **Deprecated provider usage persisted in CloudFront.** `forwarded_values` blocks remained in both `cloudfront_events.tf:58`/`:91` and `custom_resources.tf:309`/`:345`, rather than the cache-policy form AWS now favours. (The separately-flagged deprecated `aws_region.current.name` was fixed.)
- **Repository still carried iteration artifacts.** `converted-user-service.yml` (402 lines) remained tracked at the repository root; the website directory tracked a Playwright report and a test-results tree (`website/playwright-report/*`, `website/test-results/*`) including a `.last-run.json` recording a **failed** run, two `.webm` videos, and failure screenshots; `examples/lambda/.terraform.tfstate.lock.info` (a Terraform state lock file) was tracked.

**Node layer.** `sam-preprocessor.js` (540 lines) remained the most critical and least-tested code: it had **no direct JavaScript unit tests** at this commit, covered only indirectly by Terraform tests that themselves require LocalStack or AWS credentials to run. The schema-generation tool (`tools/schema-generator/`) remained the counter-example: a clean loader/extractor/generator/templates pipeline with a 59-case Jest suite — though that suite was not wired into any CI workflow.

---

## 3. Database and migration design

The module had **no database and no schema migrations** in the conventional sense; it was infrastructure-as-code. The closest analog remained the **schema-generation and validation pipeline**, assessed here in that spirit.

- **Source of truth.** `schemas/serverless-framework/{v2.x,v3.x,v4.x}.json` held versioned JSON Schemas; `tools/schema-generator/` transformed them into `generated/validation-{common,v2,v3,v4}.tf`, which were committed and consumed as the module's config validation.
- **"Migration" analog — generated-code drift.** The drift control observed at the prior snapshot remained in place: `.github/workflows/validate-generated-code.yml` regenerated and compared SHA-256 checksums, failing on drift, with a runtime-budget check and a `fmt` check on `generated/`. A weekly `schema-update.yml` job fetched upstream schemas and opened PRs.
- **Provenance — improved but not in-file.** The prior snapshot's "no provenance" finding was partially addressed: `schemas/serverless-framework/README.md` now carried a provenance table (file → version → JSON-Schema draft → source URL → "Date Vendored" 2025-10-28). The residual gap was that this provenance lived in a README, not inside the `.json` files (which carried only `title` and `$schema`), and the v3/v4 entries were described as derived from community schemas and release notes rather than pinned to a specific upstream tag — so exact upstream currency still could not be answered from the schema files alone.
- **Multi-version handling.** v2/v3/v4 were handled side-by-side (Draft-04 for v2, Draft-07 for v3/v4), appropriate for a tool that must accept all three.

Net: for a module with no datastore, the schema pipeline remained the best-engineered subsystem and the one with the strongest automated guardrails — with the caveat that its own Jest suite was not run by CI.

---

## 4. Team maintainability and bus-factor risk

- **Bus factor of one.** At this commit, effectively all knowledge still resided with a single author (49 of 50 commits). The most intricate code — the `locals.tf` resolution engine, the intrinsic evaluator, the plan-known-key invariants — remained the code least amenable to being picked up cold. The dense rationale comments reduced this risk; the addition of hermetic regression tests for the recently-fixed bugs (below) reduced it further, by converting several previously comment-only invariants into executable checks.
- **Invariants now partly enforced by tests.** A material improvement since the prior snapshot: five hermetic `mock_provider`-based test files existed and passed at this commit, each pinning a specific invariant or recently-fixed bug — `api_gateway_method_keys` (path-in-key), `sam_plan_completes` (SAM conditional-type unification), `sam_env_nonscalar_guard` (loud failure on non-scalar SAM env), `typescript_native_engine` (native-TS path), and `lambda_code_source` (local-vs-S3 archiving gate). These run without LocalStack or credentials and therefore form the first genuinely portable correctness signal in the repository.
- **Concentration risk.** `locals.tf` at 1,042 lines remained the single point most likely to be edited and most likely to break in non-obvious ways.
- **Stale internal documentation.** Partly corrected, partly not. `tests/TEST_COVERAGE.md` was refreshed (it claimed 52 files / 273 runs / 571 assertions against an actual 53 / 274 / 573 — already drifted by two files since the refresh). `tests/LAMBDA_COVERAGE.md`, however, still asserted "**Total: 28 tests**" and "All tests passing," the exact stale claim flagged at the prior snapshot. The README contradicted itself on the TypeScript path: a headline "no `npm install` required for any config format" alongside a later "TypeScript Prerequisites" section instructing `npm install typescript ts-node`. `scripts/vendor/js-yaml/VENDOR.md` likewise still stated the TS path needs `ts-node`/`typescript`, which the same commit range had made untrue.
- **Cognitive load from `agent-os/`.** Unchanged: 70 of the 101 tracked markdown files lived under `agent-os/`, none of which affected module behaviour, inflating the surface a newcomer had to triage.
- **Repository hygiene.** The tracked iteration artifacts and committed website test artifacts (§2) added noise, including a committed record of a failing website test. Author identity was not normalised (three name spellings, no `.mailmap`). Consumer/fork-specific notes (`TEXE-*.md`) remained in a general-purpose module repository.

---

## 5. Delivery risk (prioritised)

1. **(High) The test suite still could not execute as a full-suite correctness gate under the module's toolchain.** This was verified directly at this commit. Of 53 `.tftest.hcl` files, ~17–18 configured the AWS provider with a `dynamic "endpoints"` block inside a `provider "aws"` block in the test file (the LocalStack dual-mode pattern templated in `tests/shared_test_config.tftest.hcl:57-71`). Running `terraform test` against any such file under Terraform v1.14.8 produced a hard error — `Error: Unsupported block type … Blocks of type "dynamic" are not expected here` (reproduced against `tests/defaults.tftest.hcl:18`). The Terraform test-framework parser does not permit `dynamic` blocks in a test-file provider configuration, independent of the AWS provider version. (The prior snapshot attributed this to AWS provider v6 specifically; the mechanism is the test-framework parser, but the consequence is identical and unresolved.) The bulk of the suite therefore still had no working automated path to green under the module's own commands.
2. **(High → latent) Provider blocks in test files referenced an undefined-to-the-framework variable.** Twenty-one test files referenced `var.use_localstack`/`var.localstack_endpoint` inside their `provider "aws"` block. Although those variables are declared in `variables.tf:129`/`:135`, the test framework does not inject module input variables into a test-file provider block; at this commit Terraform emitted a deprecation warning ("Referencing undefined variables within Terraform Test files is deprecated … This will become required in future versions"). This is a warning now and a hard failure on a future Terraform — a second, compounding reason the LocalStack-pattern files do not run cleanly.
3. **(High) The portable subset that *did* run was small but green.** The five `mock_provider` files (§4) executed hermetically and passed (12 `run` blocks across them at the time of review). This is the entirety of the suite that could be validated without LocalStack or AWS credentials. It covered the recently-fixed bugs well but a small fraction of overall behaviour.
4. **(Medium) CI signals remained divergent and partly red.** `module-tests.yml` ran only `fmt`/`validate`/`plan` over a few fixtures (no `terraform test`) and would currently fail at its `fmt -check` step (six unformatted files, §2). `test.yml` ran the full `terraform test -var="use_localstack=true"` under LocalStack and gated on the result, but would hit the `dynamic`-block error above. The net effect was the same false-confidence shape the prior snapshot described: a lightweight workflow read as the health signal while the full-test workflow was broken.
5. **(Medium) Plan-time coupling to Node remained for the TS path.** The SAM path was made offline-capable (vendored js-yaml, no `npm install`), removing that instance of the risk. The TypeScript path still shelled to Node and now required Node ≥ 22.7 with an experimental flag, or an explicitly configured `SLS_TF_TS_RUNNER`; native TS execution did not support CommonJS `require`, extensionless relative imports, or tsconfig path aliases, narrowing out-of-the-box compatibility for `serverless.ts` consumers.
6. **(Medium) Supply-chain pinning gaps in CI persisted.** `aquasecurity/trivy-action@master` remained unpinned in `module-tests.yml:215` and `website-deploy.yml:178`; Terraform versions across workflows were inconsistent (`~1.5`, `1.5.0`, `1.8`) while the module declared `required_version >= 1.0.0` with `aws >= 6.0`.
7. **(Low) Tracked artifacts and stale docs** (delivery-adjacent): iteration files, committed website test artifacts including a failing-run record, a tracked state lock file, and the `LAMBDA_COVERAGE.md` / README / `VENDOR.md` contradictions erode trust and slow review rather than break builds.

---

## Correctness bugs identified, with production impact

Each item below was checked against the source at `f4f00dd1`. The high-severity defects recorded at the prior snapshot (`3cca7f5d`) were re-verified and found **fixed** at this commit (API Gateway path-in-key; SAM "Inconsistent conditional result types"; the unreachable size-validation warning; the deprecated `aws_region.current.name`; the TypeScript path-interpolation hazard). The items below are those still present at this commit.

1. **Conditionally-gated IAM policy statements could still be silently dropped.** `sam-parser.tf:329-333` filtered out statements whose resolved `Resource` list was empty (e.g. an `!If` branch resolving to `AWS::NoValue`). **Impact:** a statement intended to be present under some conditions can vanish with no error, leaving a function under-permissioned at runtime — a failure that surfaces only when the code path needing the permission executes. Severity: medium. (Unchanged from the prior snapshot.)

2. **CloudFront still used the deprecated `forwarded_values` block.** `cloudfront_events.tf:58`/`:91` and `custom_resources.tf:309`/`:345`. **Impact:** distributions generated with a structure AWS has deprecated in favour of cache policies; functional at this commit but on a deprecation path that a future provider major may remove. Severity: medium (forward risk).

3. **`${env:}` resolution remained bounded to three references per value; `${self:}` to an enumerated path set; strict mode inspected only top-level keys.** `variable_resolution.tf:280-350`. **Impact:** a config value containing four or more `${env:}` references, or a `${self:}` reference to a non-enumerated nested path, resolves only partially and the literal `${…}` survives into generated resources. With `strict_variable_resolution` off this is silent; with it on, the strict check (`variable_resolution.tf:345-350`) iterates only `resolved_config`'s top-level keys, so unresolved references nested inside `provider`/`custom`/`functions` can pass even in strict mode. Severity: medium (silent wrong value in generated infra). (Unchanged.)

4. **`var.max_variable_depth` was inert.** Declared and validated (`variables.tf:162-171`) and surfaced as a configurable knob in documentation, but never consumed by the resolution engine (the passes are hardcoded to three). **Impact:** an operator raising `max_variable_depth` to resolve deeper variable chains observes no change; the limit silently remains three. Severity: low (misleading configuration surface, not a wrong deployment). (New observation at this commit.)

5. **FIFO-queue detection keyed on an `.fifo` ARN suffix would not recognise SAM `!Ref` logical IDs.** `locals.tf:713-737`. For SAM SQS events the queue reference is preserved as a `!Ref` logical-ID string (`sam-parser.tf:134-139`), which carries no `.fifo` suffix, so a FIFO queue referenced this way is treated as a standard queue and validated against the standard-queue batch-size bound (1–10) rather than the FIFO bound (1–10000). **Impact:** a valid SAM FIFO configuration with a batch size between 11 and 10000 would be rejected by validation. Severity: low (validation-only; blocks a valid config rather than producing wrong infrastructure). (Carried forward from the prior snapshot's lower-confidence list; the code path is unchanged.)

6. **`sam-preprocessor.js` resolved unknown conditions fail-open.** `scripts/sam-preprocessor.js:278` defaulted an unrecognised condition name to `true`. **Impact:** a SAM resource gated on a misspelled or missing condition is *included* in the plan rather than excluded, potentially materialising infrastructure the template author intended to suppress. Severity: low–medium (depends on the gated resource). (New observation at this commit.)

Delivery-class defect, recorded here because it blocks validation rather than deployment: the test-suite `dynamic "endpoints"` and undefined-variable issues (§5, items 1–2) prevented the bulk of the suite from running. This is the same class of masking the prior snapshot warned about — high-severity defects had previously hidden behind an unrunnable suite — and remained the central delivery risk.

---

## Strategic assessment

At this commit, the evidence favoured **(B) continuing the targeted refactor and stabilisation pass already in progress** — not (A) continuing as-is and not (C) rewrite.

- **Against (C) rewrite.** The hardest, most valuable parts remained solved and were, at this commit, being actively defended: the single-internal-representation design, the plan-known-key invariants (now hardened with `nonsensitive()` at the boundary), and the intrinsic evaluator. A rewrite would discard real, non-obvious domain knowledge for no architectural gain. The architecture was not the problem at this commit and had, if anything, been reinforced.
- **Against (A) continue as-is.** The module still had, at this commit, no working full-suite correctness gate (the test-framework `dynamic`-block and undefined-variable issues), while carrying concentrated complexity in one 1,042-line file and several latent correctness defects. The recently-landed fixes demonstrably worked, but they were validated by a handful of hermetic tests; the majority of behaviour remained unguarded.
- **For (B).** The trajectory between the two snapshots is itself evidence for (B): in the commits since `3cca7f5d`, the two highest-severity bugs were fixed *and* given hermetic regression tests, the SAM plan-time toolchain dependency was removed, and a code-injection-shaped hazard was eliminated. The work that remained was the same bounded, mostly mechanical-to-moderate set the prior snapshot identified — finish migrating the test files off the unrunnable `dynamic "endpoints"` provider pattern (the five `mock_provider` files show the working pattern already exists in-repo), decompose `locals.tf`, address the remaining enumerated defects, and reconcile the contradictory docs.

**Tradeoffs.** (B) continued to front-load unglamorous test-infrastructure work before the next feature. The cost of deferring it was unchanged and concrete: with the full suite unrunnable, the bus-factor-of-one author remained the only safe editor of the most critical file, and regressions outside the five hermetic tests could not be caught automatically — the precise conditions under which the just-fixed defects had originally shipped.

---

## Prioritised fix list (ordered)

**Immediate (restore the ability to validate changes):**
1. Migrate the ~17–18 test files that use `dynamic "endpoints"` inside a `provider "aws"` block onto the working `mock_provider` pattern already used by the five passing hermetic tests, or onto a static endpoints form the test framework accepts, so `terraform test` runs at all.
2. Add `variable` blocks (or remove the references) for `var.use_localstack`/`var.localstack_endpoint` inside test-file provider blocks, clearing the deprecation that will become a hard failure on a future Terraform.
3. Make CI honest and green: wire a workflow that actually runs the runnable `terraform test` subset and gates on it; fix the six `fmt`-failing files so `module-tests.yml`'s `fmt -check` passes; stop treating the plan-only workflow as proof of test health.

**Before next release:**
4. Decide CloudFront's deprecation path: migrate `forwarded_values` (`cloudfront_events.tf`, `custom_resources.tf`) toward cache policies, or document the deprecation explicitly with a removal plan.
5. Either consume `var.max_variable_depth` in the resolution engine or remove the knob; lift or explicitly document the fixed `${env:}` three-pass / enumerated `${self:}` limits as hard bounds with a validation error when exceeded; make `strict_variable_resolution` inspect nested values.
6. Surface, rather than silently drop, IAM statements whose `Resource` resolves empty (`sam-parser.tf:329-333`) — emit a validation error or a marker instead of filtering.
7. Make `sam-preprocessor.js` fail-closed (or warn) on unknown condition names (`scripts/sam-preprocessor.js:278`); align `!Equals` with CloudFormation semantics.
8. Add direct unit tests for `scripts/sam-preprocessor.js` (the untested 540-line evaluator), and wire the existing `tools/schema-generator/` Jest suite into CI.

**Longer-term (reduce bus-factor and concentration risk):**
9. Decompose `locals.tf` (1,042 lines) along its pipeline seams (parse / validate / resolve / events / IAM), and continue converting comment-only invariants into hermetic tests of the kind already added.
10. Pin CI actions (`trivy-action@master` → a version/SHA) and standardise the Terraform version across workflows.
11. Reconcile the contradictory documentation (README TypeScript prerequisites vs the zero-dependency claim; `VENDOR.md`'s stale ts-node note; `LAMBDA_COVERAGE.md`'s "28 tests / all passing"); remove tracked iteration and test artifacts (`converted-user-service.yml`, `website/playwright-report/*`, `website/test-results/*`, `examples/lambda/.terraform.tfstate.lock.info`); add a `.mailmap`.
12. Embed provenance (upstream tag and fetch date) inside the schema JSON files, not only the README; reconsider whether `agent-os/` (70 of 101 markdown files) and the consumer-specific `TEXE-*` notes belong in this repository.
13. Add an `examples/README.md` so the example configs document their own intent.

---

## Final verdict (scored as of commit `f4f00dd1`, 2026-06-06; out of 10)

- **Confidence in correctness — 6/10.** *Higher than the prior snapshot: the two top-severity bugs are fixed and regression-tested, but several latent defects remain and the full suite still cannot run as a gate.*
- **Maintainability — 5/10.** *Strong, now partly executable, rationale offset by a still-growing 1,042-line hotspot, contradictory docs, and tracked artifacts.*
- **Scalability (feature and config growth) — 5/10.** *Clean single-representation core and a now-offline SAM path, but the hardcoded depth/pass/path limits — and an inert depth knob — still cap growth silently.*
- **Onboarding — 4/10.** *Good local comments and a small portable test set, undercut by a bus-factor of one over the hardest code, self-contradicting install docs, a stale coverage file, and 70 ancillary `agent-os/` documents.*
- **Production readiness — 5/10.** *Generating real infrastructure for live consumers with the recently-reported consumer bugs fixed, yet still shipping with a full test suite that cannot execute under its own toolchain.*

These scores describe the repository at one instant. They are not a judgement of the author or of the module's trajectory — which, measured against the prior snapshot, was corrective and improving — and they should not be read as current once any of the listed fixes have landed.
