# Harness for Salesforce — A Cross-Sell Play

**A one-page product brief for the Salesforce DevOps opportunity, from your interview candidate.**

---

## The thesis

Harness's existing enterprise customers already spend on Salesforce DevOps — they spend it with **Copado, Gearset, and Flosum**. That's the wedge. Not new-customer acquisition — capturing Salesforce budget from accounts that already trust Harness for the rest of their delivery pipeline.

## The market gap

Salesforce DevOps is a **~$1B and growing** market. The three incumbents combined lack what Harness naturally has: a first-class governance, observability, secrets, and pipeline-as-code posture that enterprise customers demand for the rest of their software delivery. Meanwhile Harness today ships basic Salesforce support (`sf` CLI invoked from CI stages) that is genuinely useful for pro-code developers — but **fails the admin-developer**, who is the actual majority of Salesforce change-makers. Copado and Flosum built their businesses on admin-developer experience; Gearset on the *dependency-aware comparison and deploy engine* that admin-developers need to ship safely.

## Where Harness wins

Two capabilities Harness has natively that the incumbents either don't have or bolted on later:

1. **Enterprise governance primitives already exist.** Approval gates, output-variable-carrying quick-deploy, secrets management, audit trails, deployment freezes, IDP integration. Copado charges enterprise-tier prices to replicate a subset of these; Gearset doesn't have them; Flosum lives inside Salesforce and inherits its governance limits.
2. **Cross-sell velocity.** Existing Harness enterprise customers already have contracts, budget approvers, and security reviews cleared. Landing a Salesforce practice in those accounts is a **quarters-to-months sales cycle**, not multi-year — because the vendor already has SOC 2, procurement paperwork, and a champion inside the account.

## What the demo repo shows

Built against a fresh Harness Free-tier account and two Salesforce Developer Editions in the week before this interview:

| Artifact | What it proves |
|---|---|
| **Salesforce DX Governed Release** pipeline (5 stages) | I know the enterprise release pattern — validate → sandbox → validate prod → approval → quick-deploy — end to end, wired to real Harness secrets and JWT-authenticated Salesforce Connected/External Client Apps |
| **Salesforce Feature Package Deploy** pipeline (dep-resolver) | I built the missing intelligence layer as a Harness pipeline stage — the same Gearset "comparison and deploy" pattern surfaced natively in Harness |
| **`docs/dep-resolver-architecture.md`** | I know what a real dependency engine costs (8-10 engineer-months for v1, 12-18 months for parity), what shortcuts are safe, and what the roadmap looks like |
| **`docs/pipeline-setup-runbook.md`** | I write customer-facing implementation runbooks, not just code |

## What I'd propose Harness ship

- **Q1:** Salesforce Feature Package Deploy as a first-class Harness template (based on the dep-resolver in this repo). Enterprise customers using Harness CI/CD can start feature-independent Salesforce promotions in one release cycle.
- **Q2:** Coverage expansion — dep-resolver hits parity with Gearset comparison for the top ~20 metadata types. Real formula parser, Flow and Layout walkers, managed package awareness.
- **Q3:** Cross-org compare-and-suggest — "you changed these 3 items in dev; deploy this package." **This is the moment Gearset renewals stop and Harness cross-sell revenue lands.**
- **Q4:** Admin-developer UI — searchable metadata browser, seed-manifest builder, visual dependency graph, approval flow that lives outside YAML. **This is the moment Copado and Flosum renewals stop.**
- **Q5+:** Harness AIDA meets the dep-graph. "Given this Jira ticket, suggest the seed manifest. Given this PR, predict deployment health." First-mover on AI-assisted Salesforce DevOps.

## The ask

I'm interviewing for **Senior Implementation Engineer**. Given what's in this repo, I'd like to also talk with whoever owns Salesforce product strategy about how this thesis fits their roadmap. Whether that's Principal Customer Architect, a founding role on a Salesforce practice, or a title that doesn't exist yet — I'll do great work at Senior IE regardless, and I want to earn the swing at building the practice from the inside.

---

**Repo:** github.com/joenormousman/Harness
**Interview candidate:** Joe Norman
**Domain expertise:** DevOps + Salesforce (Gearset, Copado, Flosum architect)
