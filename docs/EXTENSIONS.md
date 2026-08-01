# Extensions: a first-class concept for non-SAM, non-Serverless behaviour

**Status:** implemented in v0.11.0. See [Migration](#migration) for what shipped
and how it differed from this proposal.
**Motivating incident:** a consumer wrote a full alarm configuration against a
module version that predated alarm sets, and got silence — no error, no warning,
a clean `terraform validate`, and zero alarms. Detail in
[The failure that motivates this](#the-failure-that-motivates-this).

---

## The problem

sls.tf's contract is *"point it at a Serverless Framework or SAM config and get
Terraform"*. That contract is the product: a developer who knows SAM contributes
without learning Terraform.

But real consumers need things neither format expresses. Migrating event-service
off `elemental-event-driven-service` needed dynamic alarm sets, an auto-generated
dashboard, and a self-provisioned custom domain — none of which exist in SAM or
Serverless Framework core. Those landed as **extensions**: config that sls.tf
understands and no other tool does.

Three exist:

| Extension | SAM key | Serverless-yaml key | Implementation |
|---|---|---|---|
| Alarm sets | `Metadata.SlsTf.Alarms` | `custom.slsTf.alarms` | `alarm-sets.tf` |
| Dashboard | `Metadata.SlsTf.Dashboard` | `custom.slsTf.dashboard` | `dashboard.tf` |
| Custom domain | `Metadata.SlsTf.CustomDomain` | `custom.slsTf.customDomain` | `http-api-domain.tf` |

All three moved to this namespace in v0.11.0. There are no aliases for the old
spellings (`alarms:`, `dashboard:`, `provider.customDomain`) — a config still
using one gets a plan-time error naming the replacement.

They work. **The problem this document addressed** was that they arrived one at a
time, each inventing its own conventions, with nothing tying them together. The
five points below describe the state before v0.11.0; each is answered by a
numbered section under [Proposal](#proposal):

1. **The namespace is inconsistent across formats.** SAM gets a vendor-scoped
   `Metadata.SlsTf.*`; serverless yaml gets bare top-level keys. So `alarms:` in
   a serverless config is indistinguishable from a hypothetical future upstream
   `alarms:`, and a reader can't tell which keys are ours.
2. **Unknown keys are silently ignored.** Every lookup is
   `try(..., {})`. Typo the key, use an extension the pinned version doesn't
   have, or hold a config for an extension that was renamed — all identical to
   "no config". This is the failure mode that actually bit.
3. **There's no way to ask what's supported.** No output, no variable, no
   validation listing the extensions a given version implements. Consumers
   discover support by reading the CHANGELOG or by deploying and looking.
4. **Which parse an extension reads from is undocumented and load-bearing.**
   Alarm sets read the *structural* parse, where any parameter not named in
   `structural_sam_parameters` silently resolves to its template `Default`. A
   `!Ref` to an SNS topic parameter therefore resolves to the Default unless the
   consumer knows to declare it. Nothing says so; nothing checks.
5. **Extensions and genuine CFN overlap confusingly.** `cloudwatch-observability.tf`
   maps real `AWS::CloudWatch::Alarm` resources from the `resources:` section —
   that is *not* an extension, it's standard CFN support. But it sits next to
   `alarm-sets.tf` which *is* one, and both produce alarms. A consumer asking
   "how do I get an alarm?" has two answers with no stated guidance on which.

Point 5 is the "muddying the waters" concern, and it's real: **the alarm work
conflated two different things** — implementing a CFN resource type sls.tf didn't
support yet, and inventing a config shape that no spec defines. Those deserve
different treatment, different guarantees, and different places in the docs.

## Design goals

- **Invisible unless used.** A config with no extension keys must behave exactly
  as it does today. No new required inputs, no behavioural change, no new
  resources. This is the "isolated from standard behaviour" requirement.
- **Loud when wrong.** An extension key that isn't recognised, or is recognised
  but unsupported by this version, must fail the plan with a message naming the
  key and the version that introduced it. Silence is the bug.
- **One obvious way in.** Same namespace, same shape, both config formats.
- **Local SAM tooling keeps working.** Extensions must live somewhere
  `sam validate` and `sam build` accept without complaint, so the template stays
  usable with `sam local invoke` / `sam local start-api`. `Metadata` is the only
  location CloudFormation *specifies* as inert, which is why it was chosen —
  worth stating explicitly, because it's the constraint that rules out most
  alternatives. The serverless-yaml equivalent is `custom:`, inert by the same
  kind of guarantee.
- **Cheap to add.** If declaring an extension costs a registry entry plus a
  handful of validation lines, people will keep adding them properly. If it
  costs a design meeting, they'll go back to bare `try()` lookups. (Schema-driven
  validation was considered and deferred — see
  [EXTENSION-SCHEMAS.md](EXTENSION-SCHEMAS.md).)

### Explicit non-goal: `sam deploy` on an extended template

Living in `Metadata` means CloudFormation *ignores* extensions. So
`sam deploy template.yaml` produces a stack with no alarms, no dashboard and no
custom domain — silently, cleanly, exit code zero. That is the same
silence this document exists to eliminate, relocated from version skew to tool
choice, and worse in one respect: version skew is visible in a lockfile, whereas
"someone ran `sam deploy`" leaves no trace beyond the missing resources.

`sam deploy` on a template carrying extensions is therefore a **partial deploy**
and is not supported. The portability that `Metadata` buys is local-tooling
portability, not deployment portability, and the docs should not imply
otherwise. [Sidecar packaging](#7-sidecar-packaging-slstfyaml-and-the-sam-deploy-path)
below is the route to a supported SAM-deploy path; it works by *completing* the
deploy rather than by pretending the subset is equivalent.

## Proposal

### 1. One namespace, both formats

```yaml
# SAM (template.yaml) — Metadata is ignored by CloudFormation
Metadata:
  SlsTf:
    Alarms: { ... }
    Dashboard: { ... }
    CustomDomain: { ... }

# Serverless Framework (serverless.yml) — custom: is schema-free by design
custom:
  slsTf:
    alarms: { ... }
    dashboard: { ... }
    customDomain: { ... }
```

Same extension names, same sub-schemas, one place to look per format.

**The namespaces mirror each other by mechanism, not by position.** `Metadata`
was chosen because CloudFormation *specifies* it as inert; `custom:` is inert
for Serverless Framework by the same kind of guarantee, and is where SF plugins
have always put their config. A bare top-level `slsTf:` would mirror the visual
position of `Metadata.SlsTf` while breaking the property that made the SAM
choice correct: SF treats unknown root keys as unrecognised properties — a
warning under the default `configValidationMode: warn`, and a hard failure under
`error`. Legitimising a root key means registering it through an SF plugin's
`defineTopLevelProperty`, i.e. shipping a plugin for the sole purpose of
declaring one key. Not worth it. Casing follows each format's own convention:
PascalCase under `Metadata`, camelCase under `custom`.

**There are no aliases for the old top-level keys.** The original plan kept
`alarms:` and `dashboard:` indefinitely for event-service parity, but nothing
had adopted them in a deployed configuration — event-service is early and not
deployed with any of this. Carrying two spellings forever would have been
compatibility with nobody, at the cost of a permanently ambiguous namespace.

A config still using one is a plan-time **error** naming the replacement, not a
silent no-op:

```
Error: Extension 'Alarms' is configured at 'alarms:', which moved to
'custom.slsTf.alarms' in v0.11.0. The old key is not read, so leaving it here
would deploy none of this config while looking like it does. Move it under
custom.slsTf.
```

Ignoring the old key silently would have reproduced the exact failure this
document exists to remove.

**`provider.customDomain` moves too**, and gets the same error. It is the one
existing yaml key that sits inside a section SF *does* schema-validate, so it
has the problem this section exists to avoid. It becomes
`custom.slsTf.customDomain`. Unlike the two bare
top-level keys this is a genuine move rather than an alias: the only consumer
is not yet live, so there is nothing deployed to keep working. Scope is five
fixtures under `tests/fixtures/custom-domain-*.yml`,
`tests/custom_domain.tftest.hcl`, and the read at `main.tf:567`. It travels with
the removal of `enable_custom_domain` (§8), which touches the same lines. The
SAM path is unaffected —
`sam-parser.tf:504` synthesises the same internal shape from
`Metadata.SlsTf.CustomDomain`, and that synthesis is an implementation detail
either way.

### 2. A registry, not scattered lookups

One declared list of extensions — name, since-version, stability, config schema
reference, and the locals the implementation reads. Every extension resolves
through it rather than reaching into `local.sam_structure` directly. The registry
is what makes 3 and 4 below possible at all.

### 3. Fail on unknown and unsupported keys

Given the registry, any key under the namespace that isn't a registered
extension is a plan-time error:

```
Error: unknown sls.tf extension "Alarm" under Metadata.SlsTf

  Did you mean "Alarms"? Extensions supported by sls.tf v0.6.0:
    CustomDomain (since v0.5.0)

  "Alarms" was introduced in v0.7.0 — this module is pinned to v0.6.0.
```

That message is precisely what the motivating incident needed and did not get.
Note the second half: distinguishing *misspelled* from *not in this version* is
the high-value case, because version skew is silent in a way typos usually
aren't.

### 4. Declare which parse an extension reads

Each registry entry states whether its config is read from the structural or the
resolved parse. For structural extensions, the framework validates that any
`!Ref` appearing in the config names a parameter listed in
`structural_sam_parameters`, and errors if not:

```
Error: extension "Alarms" references parameter "AlertsSnsTopicArn"

  Alarms is read from the structural parse, where parameters not listed in
  `structural_sam_parameters` resolve to their template Default rather than the
  value you pass. Add "AlertsSnsTopicArn" to structural_sam_parameters, or the
  alarms will notify whatever the Default is.
```

Today this is tribal knowledge that costs a silent misconfiguration to learn.

### 5. Report what's active

An output — `extensions_active` — listing resolved extensions and their versions,
so consumers can assert in tests and see it in plan output. Cheap, and it turns
"did my config take effect?" from a deploy-and-check into a plan-time answer.

With presence as the enablement signal (§8) this output is the *complete*
answer, not a hint: there is no second flag that could still be off. It must
derive from the structural parse, or it will be unknown at plan for exactly the
configs people most want to assert on.

### 6. Separate extensions from CFN coverage in the docs

`AWS::CloudWatch::Alarm` support is **not** an extension — it's sls.tf doing its
actual job for a resource type it hadn't covered. Alarm *sets* are an extension.
The docs should say, in one place:

> Need a specific alarm? Declare `AWS::CloudWatch::Alarm` in `resources:` —
> standard CFN, portable to any tool.
> Need "one alarm per lambda, whatever the set turns out to be"? That's not
> expressible in CFN. Use the `Alarms` extension, which is sls.tf-only.

Same for dashboards. Stating the trade-off — portability versus dynamism —
resolves the "two ways to get an alarm" confusion without removing either.

### 7. Sidecar packaging (`slstf.yaml`) and the SAM-deploy path

`Metadata` is the right default for the Terraform path: one file, nothing to
keep in sync, and it's what event-service and identity-service already run in
production. But it is *packaging*, not the extension model, and a second
packaging unlocks something `Metadata` can't offer — a supported `sam deploy`.

A sidecar is a separate file beside the template:

```
template.yaml     # pristine SAM — sam validate/build/deploy all honest
slstf.yaml        # extensions, in the same shape as Metadata.SlsTf.*
```

Nobody can mistake `slstf.yaml` for something CloudFormation reads, so the
false-equivalence problem disappears at the source. More usefully, an
independently addressable file can be handed to an applier that is not
Terraform — which makes "deploy everything sls.tf would deploy, without
Terraform" a real workflow for sandboxes and less controlled environments,
rather than a partial deploy with a warning attached.

**The extension logic is already deployer-agnostic.** `_alarm_class_all_names`
(`alarm-sets.tf:58`) enumerates entirely from the structural template parse — no
resource attributes, no state. Alarm sets and dashboards are pure functions of
the template today, which is most of the work an alternative applier would
otherwise need.

**The catch is name prediction, and it is the whole risk.** Where a resource
omits an explicit name, the enumeration predicts *sls.tf's* convention
(`${service}-${stage}-${key}` for functions, `to_snake_case(LogicalId)-${stage}`
for tables/buckets/rules). Under `sam deploy` CloudFormation assigns
`stack-LogicalId-AB12CD34` instead, so every predicted name is wrong and the
resulting alarms sit in `INSUFFICIENT_DATA` forever — silent, again.

Two ways out, and v1 should take the first:

1. **Require explicit names.** The divergence only affects resources that omit
   one, and explicit names are already the recommended posture — it's what
   `check "lambda_naming_convention"` warns about for brownfield. Sidecar mode
   validates that every enumerated class member has an explicit name in the
   template and errors with the naming-lint message if not.
2. **Source names from the deployed stack** (`describe-stack-resources`) instead
   of predicting them. Strictly better — real names, no prediction — and it
   would improve the Terraform path too. A later enhancement, not a
   precondition.

**Applier: generate a companion CloudFormation template.** Of the three options
considered — an extensions-only mode of this module, a standalone Node CLI, and
a generated companion stack — the third is the one to build:

| Option | Verdict |
|---|---|
| Extensions-only mode of this module | Cheapest (reuses `alarm-sets.tf` verbatim), but drags Terraform state into the scenario that was trying to avoid it, and puts two tools on one stack's resources. |
| Node CLI | No state — which reads as a feature until an alarm must be *deleted* because the sidecar changed, and reconciliation gets hand-written. |
| **Companion CFN template** | `slstf.yaml` → `extensions.yaml`, deployed as a sibling stack. Alarms, dashboards and domains are all plain CFN; the dynamism lives at generation time, where it belongs. Lifecycle and deletion come free from CloudFormation. No new runtime, no state file. |

The sandbox story becomes two `deploy` commands. The hazard doesn't vanish —
`sam deploy template.yaml` alone is still incomplete — but it stops being "you
deployed a lie" and becomes "you ran one of two commands": documentable,
enforceable in CI, and detectable by the absence of the sibling stack.

**Resolution rules.** The sidecar is an *additional* source, not a replacement.
The registry (§2) already centralises lookup, so a second source is one more
entry in the resolution chain. Defining the same extension in both
`Metadata.SlsTf` and `slstf.yaml` is an **error**, not a documented precedence
order — silent precedence is the failure mode this whole document is about.

**Settled during implementation:**

- *Where the generator lives* — `tools/extension-stack`, Node, alongside
  `schema-generator`. Unlike that tool it is dependency-free: YAML comes from
  the js-yaml already vendored under `scripts/vendor/`, and the output is JSON,
  which CloudFormation accepts and which needs no serialiser. Nothing to
  install, matching the module's own posture.
- *How the sidecar finds its template* — neither. The **module** takes an
  explicit `extension_sidecar_path`, and the **generator** takes both paths as
  arguments. Discovery by filename was rejected: a sidecar found by convention
  could be renamed or lost and simply stop applying, which is the silence this
  whole document exists to remove. Naming it makes a missing file an error.
- *Where the explicit-names precondition lives* — the generator only. See
  Migration step 6.

### 8. Presence is enablement — no per-extension boolean

An extension is active if and only if its config is present. No `enable_*`
variable gates one.

Alarm sets and dashboards already work this way. `CustomDomain` does not, and
the consequence is the motivating incident in miniature, shipped in the module
today:

```hcl
# variables.tf:107 — defaults to false
variable "enable_custom_domain" { type = bool, default = false }

# main.tf:567
count = var.enable_custom_domain && try(local.provider_with_defaults.customDomain, null) != null && ...
```

Write a complete, valid `customDomain` block, don't happen to set the variable,
and you get zero resources, no error, clean plan. Same silence, same shape,
different cause. A boolean that must agree with the config is a second place for
the config to be wrong, and the failure is always silent in the same direction.

So `enable_custom_domain` is **removed**, not deprecated. Terraform hard-errors
on `Unsupported argument`, which is the loud failure this document keeps
choosing — and it's the same property that makes `required_extensions` work.
The two inputs are complements, not duplicates: presence *enables*,
`required_extensions` *asserts* that the pinned module version can honour what
is present. Neither can be silently wrong.

`create_hosted_zone` (`variables.tf:113`) should move with it, to
`customDomain.createHostedZone` — it's a behaviour choice a YAML file can
express, it's per-domain, and it's in the same files and tests. Less urgent than
the enable flag, because getting it wrong currently fails loudly
(`modules/custom-domain/validation.tf:48`) rather than silently. Separable if
the churn isn't wanted in one change.

**`acm_certificate_arn` (`variables.tf:119`) stays a variable**, and the reason
is the boundary rule worth writing down:

> Config that describes *what the consumer wants* belongs in the extension.
> Wiring that can only come from Terraform — a co-planned resource attribute, a
> remote-state lookup — stays a module variable.

An ACM certificate ARN is frequently `aws_acm_certificate.this.arn` from the
caller's own configuration, which no YAML file can name. That is the test to
apply before moving anything else: can the value exist in the config file at
all? If not, it isn't an extension.

## The failure that motivates this

A consumer (identity-service, PLAT-295) added a full alarm configuration:
`Metadata.SlsTf.Alarms` with a lambda group over `resource_names: []`, a custom
namespace group, an SNS topic parameter, and `structural_sam_parameters` wired to
resolve it.

Their module is pinned to **v0.5.6**. Alarm sets landed in **v0.7.0**.

Everything passed. `terraform validate` passed — `Metadata` is inert template
data. `terraform fmt` passed. The template-parity guard passed. Unit tests
passed. It would have merged, applied, and produced **zero alarms**, with the PR
description claiming monitoring was delivered.

It was caught only because someone checked `.terraform/modules/` by hand for
`alarm-sets.tf`. Nothing about the system would have told them.

Two properties turned a version skew into a silent no-op:

- `try(local.sam_structure.Metadata.SlsTf.Alarms, {})` — absent and unsupported
  are the same value.
- Nothing reports the supported extension set, so "is this version new enough?"
  has no answer short of reading module source.

Both are fixed by the registry plus fail-on-unknown. Neither needs the extension
*implementations* to change.

## Migration

**Status: all six steps shipped in v0.11.0.** Implementation order differed from
the numbering below — the yaml namespace (4) landed before unknown-key errors
(3), because unknown-key detection needs a namespace to exist in both formats
first.

| # | Step | Status |
|---|---|---|
| 1 | Registry + `extensions_active` output | shipped v0.11.0 |
| 2 | Route existing lookups through the registry | shipped v0.11.0 |
| 3 | Unknown-key and misspelled-namespace errors | shipped v0.11.0 |
| 4 | `custom.slsTf.*` namespace, `customDomain` move | shipped v0.11.0 |
| 5 | Structural-parse mismatch check | shipped v0.11.0 |
| — | `required_extensions` input | shipped v0.11.0 |
| — | `module_version` + `make check-version` | shipped v0.11.0 |
| 6 | Sidecar packaging (§7) | shipped v0.11.0 |

What shipped, and what changed from the plan:

1. **Registry** (`extensions.tf`) with all three extensions, plus the
   `extensions_active` output. Per-extension resolutions are separate `locals`,
   not fields of one map: `sam-parser.tf` reads the CustomDomain one to build
   `parsed_config`, while the Alarms and Dashboard ones read `parsed_config`
   back — as a single local that is a dependency cycle.
2. **Lookups routed through it.** Intended as a pure refactor, and it was —
   except that the new SAM fixture exposed a bug the refactor then fixed:
   `Metadata.SlsTf.Alarms` aborted the plan with *Inconsistent conditional
   result types* whenever it was non-empty, because the lookup encoded to JSON
   outside the conditional and an object with attributes does not unify with
   `{}`. Broken since v0.7.0; invisible because every alarm-set test used the
   yaml path, whose empty value is `null` and therefore unifies. **SAM alarm
   sets had never worked.**
3. **Unknown keys and misspelled namespaces** are plan-time errors, with
   `extension_unknown_key_behaviour = "error" | "warn"` as the escape hatch.
   Duplicate spellings are deliberately not downgradable. Strictness is scoped
   to `Metadata.SlsTf` / `custom.slsTf` and never the parent, pinned by a
   fixture carrying `webpack:`, `serverless-offline:` and `myOwnThing:` under
   `custom:`.
4. **`custom.slsTf.*`** is the yaml namespace, with no aliases: the old
   top-level keys and `provider.customDomain` are plan-time errors naming the
   replacement. The plan had kept them permanently for event-service parity;
   that turned out to be compatibility with nobody, since nothing had been
   deployed with them. `enable_custom_domain` and `create_hosted_zone` are also
   gone (§8).
5. **Structural-parse mismatch** ships as a `check`, diffing the extension's
   subtree between `sam_raw` and `sam_structure` — the `!Ref` search in §4 is
   unbuildable, since the preprocessor collapses refs before either parse is
   readable. Tested both ways: the mismatch is reported, and declaring the
   parameter in `structural_sam_parameters` clears it *and* points the alarm at
   the passed topic instead of the Default.

Two consequences of the module not knowing its own version, both settled:

- The §3 message that distinguishes "misspelled" from "not in this version" is
  unbuildable as written — v0.6.0 has never heard of `Alarms`. What ships names
  the offending key, the nearest match, the supported set, and the running
  version from `local.module_version`, then points at the CHANGELOG.
- Fail-on-unknown cannot help anyone still on an older pin. `required_extensions`
  is the mechanism that can, because Terraform rejects unknown module arguments
  outright. It asserts both that the version implements the extension and that
  the config actually resolved.

6. **Sidecar packaging (§7)** — `extension_sidecar_path` in the module, plus
   `tools/extension-stack` to generate the companion stack. One design point
   moved during implementation: **the explicit-names precondition belongs to the
   generator, not the module.** Under Terraform the predicted names are correct,
   so enforcing explicit names there would impose a constraint that only the
   `sam deploy` path actually needs. The generator enforces it; the module does
   not. Stack-sourced discovery remains the natural next step, and would lift
   the restriction entirely.

## Open questions

- ~~**Should extensions be opt-in per extension?**~~ **Resolved: yes, as a
  single list.** `required_extensions = ["Alarms"]` is the only proposed
  mechanism that fails loudly on a module version that predates the extension,
  because Terraform rejects unknown module arguments outright. The
  "second place to keep in sync" cost is one line, and only for consumers who
  want the guarantee. See Migration above.
- **Do extensions need their own stability levels?** `CustomDomain` is load-
  bearing for a live consumer; a future extension might want to ship
  experimental. If so, experimental ones should warn on use.
- **Where do serverless-yaml-only and SAM-only extensions sit?** No longer
  urgent — with §1's move, all three extensions exist in both formats. The
  registry should still carry a `formats` field so a future single-format
  extension has somewhere to declare itself, and so `extensions_active` can say
  why a key was ignored in the other format.
- ~~**Should the registry be data or code?**~~ **Resolved: code**, a `locals`
  map. The declarative precedent under `schemas/` is weaker than it looks —
  `generated/validation-v{2,3,4}.tf` is referenced by no `.tf` file in the
  module, so that path has never been wired up. Details and the conditions for
  revisiting are in [EXTENSION-SCHEMAS.md](EXTENSION-SCHEMAS.md).
- ~~**Which namespace in serverless yaml?**~~ **Resolved: `custom.slsTf.*`** —
  see §1. A bare top-level `slsTf:` is an unrecognised property that SF flags
  and that appears in none of the vendored schemas under
  `schemas/serverless-framework/`.
- **Does the unknown-key check cover a misspelled namespace?** As specified, no:
  `Metadata.Slstf.Alarms` isn't "an unknown key under the namespace", it's no
  namespace at all, so nothing fires and the silence is unchanged. Needs a
  sibling check for `Metadata` keys that match `slstf` case-insensitively
  without matching `SlsTf` exactly. Strictness must stay scoped to
  `Metadata.SlsTf.*` and never `Metadata.*`, which legitimately carries
  `AWS::CloudFormation::Interface`, cfn-lint config and CDK asset keys.
- **Is fail-hard the right default with no escape hatch?** Every other strict
  behaviour in this module sits behind a variable with a permissive default
  (`sam_strict_intrinsics`, `naming_convention_warning`, `s3_force_destroy`).
  An `extension_unknown_key_behaviour = "error" | "warn"` would let a large
  estate roll forward without a flag day.
