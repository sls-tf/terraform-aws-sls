# extension-stack

Turns an sls.tf **extension sidecar** into a companion CloudFormation template,
so a SAM deploy can be *completed* rather than silently missing every extension.

```bash
npm run extension-stack -- \
  --template template.yaml \
  --sidecar slstf.yaml \
  --output extensions.json

sam deploy --template-file template.yaml --stack-name my-svc
aws cloudformation deploy --template-file extensions.json --stack-name my-svc-extensions
```

No install step. YAML parsing reuses the js-yaml already vendored at
`scripts/vendor/`, and the output is JSON — which CloudFormation accepts and
which needs no serialiser. Node >= 18 (for the built-in test runner).

## Why this exists

Extensions live where the native tooling is *specified* to ignore them —
`Metadata` for SAM — so `sam validate` and `sam local` keep working. The
corollary is uncomfortable: `sam deploy` on that template succeeds and creates
none of them. Clean exit code, no alarms.

A sidecar puts the extensions in their own file, leaving the template pristine.
Nothing in it is inert vendor config, so `sam deploy` on the template is honest
about what it deploys — and this tool turns the sidecar into a second stack you
deploy alongside. Two `deploy` commands instead of one, which is documentable
and checkable in CI. The alternative is a stack that quietly lacks its
monitoring.

CloudFormation rather than a bespoke applier because alarms and dashboards
*are* plain CFN resources. The only dynamic part is deciding which ones, and
that happens here at generation time. Lifecycle then comes free: drop a group
from the sidecar, regenerate, deploy, and CloudFormation removes the alarms. A
stateless CLI applying changes directly would have to reimplement that
reconciliation by hand.

## The explicit-name requirement

This is the one real constraint, and it is worth understanding rather than
working around.

The Terraform module *predicts* names for resources that omit one, using
sls.tf's convention (`${service}-${stage}-${key}` for functions). Under
`sam deploy`, CloudFormation assigns `stack-LogicalId-AB12CD34` instead. An
alarm built from a predicted name would watch a resource that does not exist —
and an alarm on a nonexistent dimension does not fail, it sits in
`INSUFFICIENT_DATA` forever. Silent, which is precisely what all of this is
trying to stop.

So auto-enumerating groups require every resource of that class to carry an
explicit name (`FunctionName`, `TableName`, `QueueName`, …), and the error names
the ones that do not:

```
error: Alarm group 'lambda' auto-enumerates, but these lambda resources have no
explicit name: Ingest (no Properties.FunctionName). Under `sam deploy`
CloudFormation assigns a generated physical name (stack-LogicalId-XXXXXXXX), so
an alarm built from a predicted name would watch a resource that does not exist
and sit in INSUFFICIENT_DATA silently. Give each resource an explicit name, or
pin the group with an explicit resource_names list.
```

Explicit names are already the recommended posture for anything brownfield —
it is what `check "lambda_naming_convention"` warns about. Sourcing real names
from the deployed stack (`describe-stack-resources`) would lift the restriction
entirely and is the natural next step; it would improve the Terraform path too.

## Supported extensions

| Extension | Status |
|---|---|
| `Alarms` | supported |
| `Dashboard` | supported |
| `CustomDomain` | refused — needs the deployed REST API id, which is not in the template. Deploy the domain with Terraform. |

A refusal is deliberate: emitting a stack that cannot work would be worse than
saying so.

## Staying in step with the module

The generator holds its own copies of the alarm class defaults and dashboard
metrics, because it cannot read Terraform locals. Copies drift, so
`tests/parity.test.js` reads `alarm-sets.tf`, `dashboard.tf` and `extensions.tf`
directly and fails when they move — including if a new extension is registered
that the generator neither builds nor explicitly refuses. Alarm names use the
same `<group>-<metric>-<resource>` convention as the module, so the two
appliers converge on identical alarms rather than creating duplicates.

```bash
npm run test:extension-stack
```
