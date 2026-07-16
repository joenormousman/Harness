# Metadata Dependency Resolver — Architecture

This document explains what the resolver in `scripts/resolve-dependencies.py` does, what a production-parity engine would take, and what a full roadmap looks like. It's written as the technical accompaniment to the interview conversation.

## The problem in one sentence

**Salesforce metadata references each other asymmetrically, so shipping a subset without the items that depend on it — or that it depends on — leaves the target org in a broken state.**

Some concrete pairs:

| Item | What it references (forward) | What references it (inverse — asymmetric) |
|---|---|---|
| `CustomField` | Its parent `CustomObject` | `ValidationRule`s in the same object whose formula names it; `PermissionSet` / `Profile` field permissions; `Layout`s that place it; `Flow`s that read/write it; `Report`s that include it |
| `ValidationRule` | Parent object + every field inside its `errorConditionFormula` | Rarely anything — VRs are a leaf |
| `PermissionSet` | Every object/field/class/tab/app it grants access to | The users/permission-set-groups that assign it |
| `Profile` | Same as PermissionSet, larger surface | Users assigned to it |
| `ApexClass` | Any class/interface it references; any object/field it queries | `ApexTestClass`es; `PermissionSet.classAccess` |

The problem: a `CustomField` file does NOT list "here are the ValidationRules and PermissionSets that touch me." That knowledge exists only inside the files of the referrers. So to know "what must ship with this field," you have to scan sibling files.

That's why "just deploy this one field" is naïve — and why Copado, Gearset, and Flosum all sell dependency-aware deployment as their core differentiator.

## What this prototype covers

The resolver in `scripts/resolve-dependencies.py` (~350 lines, Python stdlib only) handles the first meaningful slice:

### 5 metadata types

- `CustomObject` — pulled from `objects/<Obj>/<Obj>.object-meta.xml`
- `CustomField` — `objects/<Obj>/fields/<Field>.field-meta.xml`
- `ValidationRule` — `objects/<Obj>/validationRules/<Rule>.validationRule-meta.xml`
- `PermissionSet` — `permissionsets/<Name>.permissionset-meta.xml`
- `Profile` — `profiles/<Name>.profile-meta.xml`

These 5 cover the most common daily admin-developer changes. They also cover the *hardest* asymmetry — VR formulas referencing fields, PermissionSets referencing fields — so the prototype exercises the real difficulty, not just leaves.

### Both directions of the walk

- **Forward references** — parsed from the item's own XML. A `ValidationRule`'s `<errorConditionFormula>` gets regex-scanned for `Object.Field` and `Field` tokens. A `PermissionSet`'s `<objectPermissions>` and `<fieldPermissions>` are walked directly.
- **Inverse references** — recovered by scanning sibling files. Given a `CustomField`, the resolver walks every `ValidationRule` and every `PermissionSet` looking for references TO that field. That's the *asymmetric* lookup that makes this hard.

### Rationale trail

Every included item carries a JSON trail explaining *why* it was pulled in. Example: `Release_Signal__c.Last_Run__c` shows up with three reasons:

```json
"CustomField:Release_Signal__c.Last_Run__c": [
  "lives on object Release_Signal__c",
  "referenced in Release_Signal__c.Failed_Requires_Last_Run errorConditionFormula",
  "fieldPermissions in PermissionSet Harness_Release_Observer"
]
```

The rationale trail is the interview-differentiator artifact. A resolver that just emits `package.xml` is a black box; a resolver that shows its reasoning is auditable, debuggable, and can be shown to an admin who then trusts the automation.

### Verified working

Given the seed `CustomField Release_Signal__c.Status__c` against the repo's sample metadata, the resolver expands to 5 items:

- `CustomField Release_Signal__c.Status__c` (seed)
- `CustomObject Release_Signal__c` (parent)
- `ValidationRule Release_Signal__c.Failed_Requires_Last_Run` (references Status__c in formula)
- `CustomField Release_Signal__c.Last_Run__c` (also in the formula, and referenced by the permission set)
- `PermissionSet Harness_Release_Observer` (grants access to both fields and the object)

Emitted `package-expanded.xml` is a valid Salesforce manifest fed directly to `sf project deploy start --manifest`. That's the second pipeline (`feature-package-deploy.yaml`) end-to-end.

## What's explicitly out of scope in the prototype

Written down so nobody assumes it's covered when it isn't. This list is the honest one — no hand-waving.

- **Layouts** (`Layout` type). Layouts embed field references but the schema is dense (sections, columns, items). Full support needs an XML walker.
- **Flows** (`Flow`, `FlowDefinition`). Flows reference fields, actions, subflows, and other flows. The Flow XML schema is one of Salesforce's largest.
- **Reports and Dashboards**. Cross-reference fields and objects.
- **Custom Metadata Types**. Records + type definitions with metadata-mode dependencies.
- **Managed package fields** (namespace prefixed, e.g., `npsp__Foo__c`). The resolver's regex catches `__c` fields but not namespaced ones cleanly.
- **Cross-object formula references** (`$Profile.Name`, `$User.Field__c`, relationship field traversal like `Account.Owner.Manager.Email`). Real Salesforce formulas do this constantly; the prototype's regex is single-object-scoped.
- **Formula parser** — the prototype uses regex. A real engine needs a proper parser to handle function calls, string escapes, comments, and comment-embedded field names.
- **Permission dependencies for Apex** — `PermissionSet.classAccess` and `Profile.classAccesses` reference `ApexClass` items. Resolver walks the wrapper but doesn't chase Apex class-to-class dependencies.
- **Managed package awareness** — deploying a field in a managed namespace requires the package installed in the target org first. Real engine tracks this.
- **Deleted-in-target handling** — if target has an item source doesn't, resolver has no opinion. Real engine deals with destructive changes.
- **Ordering** — resolver emits a flat set. Salesforce Metadata API deploy order matters for some pairs (Profile after CustomField, etc.). Real engine emits with dependency-ordered `types` blocks.

## What a Gearset/Copado/Flosum-parity engine takes

Honest estimate:

| Component | Person-months (conservative) |
|---|---|
| Full 250+ metadata type coverage | 4-6 |
| Real formula parser (recursive descent, not regex) | 1-2 |
| Layout / Flow / Report walkers | 3 |
| Managed package + namespace handling | 1 |
| Cross-org delta detection + destructive change generation | 2 |
| Persistent inverted index (Postgres or DuckDB) — critical for orgs with 10k+ metadata items | 1 |
| UI: seed manifest builder, rationale viewer, dependency graph visualizer | 3-4 |
| Test suite (per-metadata-type golden manifests, deploy-and-verify integration tests) | 2-3 |
| Documentation + admin-developer training material | 1 |

Rough total: **8-10 engineer-months for a v1 that would pass a Fortune 500 procurement review**, or 12-18 months if you want feature parity with the incumbents' 10-year head start on edge cases.

The tempting shortcut is "just cover the top 20 metadata types" — those account for maybe 80% of daily admin-developer changes. That's a valid MVP and a reasonable ~3-month scope. The other 20% is where the customer discovers your gaps, and Copado/Gearset don't have them.

## Roadmap I'd propose to Harness product

Ordered by both effort and revenue impact.

### Phase 1 — MVP (Q1, ~3 engineer-months)
- Top 20 metadata types (covers ~80% of admin-developer daily work)
- Regex-based formula scan (defer real parser)
- Forward + inverse walk for those 20 types
- Rationale trail (already prototyped — keep)
- Wired as a Harness pipeline stage (already prototyped — keep)
- Seed manifest authored via YAML/JSON in the repo

**Ship criterion:** existing Harness enterprise customers can promote a Salesforce feature with dependency awareness *for the metadata types they most often change*. Anything unsupported falls back to source-dir deploy with a warning.

### Phase 2 — Coverage and formulas (Q2, ~4 engineer-months)
- Add remaining ~230 metadata types via a code-generated walker (schema-driven)
- Real formula parser (~2 person-months on its own)
- Flow and Layout walkers (hardest custom schemas)
- Managed package awareness

**Ship criterion:** matches Gearset comparison coverage for the metadata types those customers actually use.

### Phase 3 — Compare and suggest (Q3, ~3 engineer-months)
- Delta detection between two orgs (metadata retrieve + hash + diff)
- "You changed these 3 items in dev; here's the package we suggest promoting" flow
- Destructive change generation
- Metadata backup for rollback

**Ship criterion:** replaces Gearset comparison workflows for Harness enterprise customers. This is the moment cross-sell revenue really lands — customers stop renewing Gearset.

### Phase 4 — UI and admin-developer surface (Q4, ~4 engineer-months)
- Web UI for seed manifest construction (searchable metadata browser)
- Visual dependency graph (which items ship together and why)
- Rationale surfaced in Harness approval messages (already in the governed-release pipeline as text — upgrade to interactive)
- Admin-developer approval flow (approve the promotion without editing YAML)

**Ship criterion:** admin-developers can drive the tool without engineering support. This is the wedge that displaces Copado/Flosum specifically — they own the admin-developer surface.

### Phase 5 — Intelligence layer (Q5+, ~ongoing)
- LLM-assisted "given a Jira ticket describing a change, suggest the seed manifest"
- Automatic conflict detection when multiple concurrent PRs touch overlapping metadata
- Deployment health scoring (predict which deploys are likely to fail before they run)

This is where Harness AIDA (already a product) meets the dep-graph. Interview note: this stage is where the current Harness AI strategy and the missing Salesforce intelligence layer naturally meet.

## Testing this in the interview

If you're asked "how did you know your resolver actually works?", the answer:

1. **Local sample metadata** — the repo has `Release_Signal__c` + 2 fields + 1 validation rule + a permission set that grants access to all of them. Real cross-references, not toy stubs.
2. **The rationale trail is verifiable by inspection** — the reasons the resolver gives for each included item can be checked against the actual XML in `force-app/`.
3. **Manifest validity** — the emitted `package-expanded.xml` conforms to the Salesforce Metadata API schema and is accepted by `sf project deploy start --manifest`. That's tested locally.
4. **What I DIDN'T test** — I did not (in the demo) test a broken input (e.g., seed with a nonexistent field). The resolver logs a warning and skips, but production would want either a hard error or a --strict mode.

If you're asked "what would you build next Monday?":

- Cross-object formula references (`$Profile`, relationship traversal). ~1 week of parser work.
- Layout coverage. ~1 week (dense schema but straightforward).
- Persistent inverted index. Not urgent for the sample, but immediately painful at 10k+ metadata items. ~2 weeks in Postgres or DuckDB.

## Where this fits in Harness's product surface

Two possible integrations, in increasing depth:

- **Shallow (this prototype's shape):** dep-resolver as a runnable pipeline stage. Customer includes it in their Salesforce release pipelines. Harness's CI runs it, sf CLI deploys the result. **This ships in a quarter.**
- **Deep (product roadmap):** first-class "Salesforce Package" resource in Harness — parallel to Services and Environments in the CD module — with a dedicated UI, a metadata browser, dependency visualization, cross-org compare, and integration with Harness approvals + observability. **This is a year of product investment**, but it's what turns Harness into the Salesforce DevOps platform, not a runner that happens to run sf commands.

The interview thesis is: **the shallow integration is a valid MVP that lets Harness reference "we support Salesforce feature-independent deployments" in one release cycle. The deep integration is where the actual cross-sell revenue against Copado/Gearset/Flosum lands.**
