# Interview Cheat Sheet — What You Built, What to Say

**Interview:** Friday 2026-07-17 with Harness Principal Engineer
**Role:** Senior Implementation Engineer
**Your differentiator:** Salesforce DevOps depth (Gearset/Copado/Flosum architect experience)

**Read this doc top to bottom tonight.** It's structured so you can defend anything an interviewer asks about what's in your Harness account and repos, without pretending to be more of a Harness expert than you are. Be honest about what you learned this week vs. what you brought in.

---

## Part 1 — What you actually have running in your Harness account

Three pipelines. Know what each one is and be able to open it live.

### 1. `DevOpsForce Site` — YOUR K8S CI/CD LAB PIPELINE (green as of today)

**What it does:** Builds a static nginx site from the `joenormousman/DevOpsForce` GitHub repo, pushes the image to DockerHub, deploys it to your GKE cluster using blue/green deployment.

**Stages:**
- **Build**
  - **Sanity Check Site** — verifies `site/index.html` exists and contains "DevOpsForce" (`alpine:3.20` image)
  - **Build and Push Image** — uses Harness's native `BuildAndPushDockerRegistry` step to build the Dockerfile and push to `joenormous/devopsforce-site:<pipelineRunNumber>` and `:latest` on DockerHub
- **Deploy** (`Deployment` stage type, not CI)
  - Service: `devopsforce_site` (Harness Service definition pulls manifests from `joenormousman/DevOpsForce` repo, artifact from DockerHub)
  - Environment: `Prod` with infrastructure `devopsforce` (targets the `devopsforce` namespace on your GKE cluster)
  - **Blue Green Deploy** — Harness's `K8sBlueGreenDeploy` step spins up a new "blue" deployment alongside the current "green"
  - **Verify Stage Color** — invokes your existing **`K8s_HTTP_Health_Check` v1 step template** (this is your bonus lab item — templatization already in production) — hits `http://devopsforce-site-stage.devopsforce.svc.cluster.local/healthz` and expects 200
  - **Swap Primary With Stage** — `K8sBGSwapServices` — swaps the service selectors so the new blue becomes primary
  - **Rollback** — if any step fails, `K8sBGSwapServices` swaps back to the previous version (defined in `rollbackSteps`)

**What the fix today was:** The K8s deployment.yaml manifest had `runAsNonRoot: true` but was missing `runAsUser: 101`. GKE's Pod Security admission requires a numeric UID to verify non-root; the base image (`nginxinc/nginx-unprivileged:1.27-alpine`) uses the named user "nginx" internally which K8s can't resolve at admission time. Added 4 lines to the deployment.yaml (`runAsUser: 101`, `runAsGroup: 101`, plus a comment), pushed to `joenormousman/DevOpsForce`, re-ran the pipeline — green.

### 2. `Salesforce DX Governed Release` — YOUR SALESFORCE DIFFERENTIATOR

**What it does:** Governed 5-stage Salesforce release pipeline demonstrating enterprise-grade metadata deployment with human approval gates and quick-deploy pattern.

**Stages:**
- **Validate Pull Request** — installs sf CLI in the workspace, JWT-authenticates to the dev org, runs `sf project deploy validate` (check-only deploy + Apex tests). Exports validation job ID and test counts as pipeline output variables.
- **Deploy Sandbox** — deploys the validated metadata to the uat org, runs `HarnessReleaseHealthTest` as a smoke test. Skipped if `deployToSandbox=false`.
- **Validate Production** — same validate flow against the production org, exports its own validation job ID.
- **Approve Production** — human approval gate. The approval message embeds the validation status, job ID, and Apex test counts from the previous stage using Harness expressions like `<+pipeline.stages.Validate_Production.spec.execution.steps.Production_Validation.output.outputVariables.VALIDATION_JOB_ID>`.
- **Deploy Production** — `sf project deploy quick` against the pre-validated job ID. Salesforce accepts a quick-deploy if the validation is <=10 days old, skipping test re-runs.

**Current state:** Imported to Harness, retargeted to your `gke_devopsforce` delegate. **Auth fails on `invalid assertion`** because the JWT cert was regenerated (v2 in scratchpad) and the new base64 isn't in the Harness secrets yet, and the new cert isn't uploaded to the SF ECAs yet. **If asked to run it live**, say: "the pipeline is deployed and structurally proven; the cert was regenerated as part of hardening and I'd need to re-upload it to both orgs and update the Harness secrets to run — 15 minutes of setup."

### 3. `Salesforce Feature Package Deploy` — YOUR THESIS DEMO

**What it does:** Reads a seed manifest (single metadata item), runs a Python dep-resolver against the repo's SFDX source tree, expands to a full `package.xml` including every dependency, deploys the expanded subset. Demonstrates feature-independent packaging — the intelligence layer Gearset/Copado/Flosum charge for.

**Current state:** YAML exists in the repo at `.harness/feature-package-deploy.yaml`, but not yet imported to Harness UI. **The dep-resolver runs locally right now**, so you can demo it in the interview by opening a terminal and running `bash scripts/run-resolver-demo.sh` — 1 seed input expands to 5 resolved items with a rationale trail explaining why each was included.

---

## Part 2 — Every technical decision, and why (be able to defend each)

### K8s cluster choice: GKE (already yours)
- **Why:** You already had this stood up from prior work; using it was faster than provisioning a new cluster and gave a real production-shape target.
- **If asked "why not Minikube/EKS/local?":** GKE was already provisioned and had a healthy Harness Delegate. Real customer engagements happen on cloud-managed K8s (GKE / EKS / AKS) more often than local; this matches that reality.

### Runtime choice: Self-hosted Delegate (`gke_devopsforce`) on your K8s cluster
- **Why:** Harness Cloud VMs (`runtime.type: Cloud`) require credit-card validation on Free tier and blocked pipeline execution. Self-hosted delegate on your GKE cluster bypasses that entirely and matches how real F500 customers deploy Harness — they run delegates inside their VPC to reach internal resources like Salesforce sandboxes without exposing them to the public internet.
- **If asked "when would you use Cloud vs Delegate?":** Cloud runtime is great for stateless public builds (open source projects, self-serve customer POCs). Delegate is required whenever the pipeline needs to reach resources inside a customer's network — Salesforce sandboxes behind IP allowlists, internal Nexus/Artifactory, private K8s clusters. Enterprise customers essentially always run delegates.

### GKE Deployment security: `runAsUser: 101` + `runAsGroup: 101`
- **Why:** GKE Pod Security admission requires numeric UIDs to verify `runAsNonRoot: true`. The `nginx-unprivileged` base image declares its user as the string "nginx" (which internally maps to UID 101), but K8s admission can't resolve string usernames at admission time — it rejects the pod. Setting `runAsUser: 101` explicitly tells K8s the numeric UID so admission passes.
- **If asked "why not just disable `runAsNonRoot`?":** Because running containers as root is a security posture I don't want to normalize. The unprivileged nginx base is already correctly non-root; the issue is only about how K8s verifies that fact. Setting the explicit UID keeps the security posture intact.

### Blue/Green deployment (over Rolling or Canary)
- **Why:** For a marketing site with predictable traffic, blue/green gives instant traffic switching + instant rollback via service selector swap. The rollout is atomic — either the new version passes health check and takes 100% traffic, or the old version keeps 100% traffic. No half-and-half state.
- **If asked "when would you pick Canary?":** Canary is right for stateful services where you want gradual traffic shift (10% new, 90% old) and metric-based promotion. It's more complex and needs strong observability. Blue/green is right when your app is stateless and you have a good health check — you get faster rollback with less risk.
- **If asked "when would you pick Rolling?":** Rolling is the default for cost-optimized long-lived deployments where you don't need instant rollback. Slower to deploy, cheaper (no double-capacity moment), but rollback is another rolling update — not instant.

### Templatization: `K8s_HTTP_Health_Check` step template (your bonus item)
- **Why:** The health check pattern — "hit an HTTP endpoint, expect a specific status" — repeats across many deployment pipelines. Extracting it as a Harness step template with `HEALTH_URL` and `EXPECTED_STATUS` as runtime inputs means every pipeline that verifies deployments references the same tested implementation. Version pinned at v1 so changes go through explicit template promotion.
- **If asked "what would you templatize next?":** On the SF side, the "Install Salesforce CLI" step appears 4 times in the governed-release pipeline + 1 time in feature-package-deploy = 5 duplications. Extracting it as a template with `SF_CLI_VERSION` as an input eliminates the duplication and standardizes CLI version pinning across every Salesforce pipeline the customer runs.

### Salesforce auth: JWT bearer flow via SF External Client App
- **Why:** Salesforce has no first-class OIDC or short-lived tokens for service accounts. JWT bearer flow is the industry-standard non-interactive auth. Requires a Connected App or External Client App in each org with a self-signed cert; the pipeline signs a JWT with the private key at runtime.
- **Modern SF nuance:** Salesforce hides "New Connected App" creation in modern orgs (2024+); you have to use the newer External Client App (ECA), which supports the same JWT bearer flow. `sf org login jwt` accepts the ECA's client_id transparently.
- **If asked "how do Copado/Gearset do this?":** Exact same JWT bearer pattern under the hood. What they add is a UI that abstracts it away from admin-developers. That's part of the wedge — Harness could ship a first-class "Salesforce Credential Setup" wizard that hides this from customers, and it would remove the biggest onboarding hurdle for the admin-developer audience.

### K8s CI vs Harness Cloud runtime: workspace-install pattern for sf CLI
- **Why:** In Kubernetes CI stages, each step runs in its own container within the pod. The workspace volume (`/harness`) is shared across steps, but anything installed globally (`npm install -g`) doesn't persist because each container is fresh. So sf CLI gets installed to `$WORKSPACE/sf-cli/node_modules/.bin`; subsequent steps `source sf-cli.env` to add it to PATH.
- **If asked "what would you optimize?":** Bake sf CLI into a custom Docker image (`joenormous/harness-sf-runner:latest`) so every step skips the ~60s install. Would also let you pin exact sf CLI + Node versions once instead of per-pipeline. That's the production-real version; the workspace-install pattern is the portable-across-any-image version.

### Salesforce metadata dep-resolver (your product thesis)
- **Why the problem exists:** Salesforce metadata references are ASYMMETRIC. A ValidationRule knows the fields its formula references. A CustomField does NOT know which ValidationRules or PermissionSets touch it. So "deploy this one field" fails or leaves the target org broken unless something scans sibling files to find inverse references.
- **What the prototype covers:** 5 metadata types (CustomObject, CustomField, ValidationRule, PermissionSet, Profile), both forward references (parsed from the item's own XML) and inverse references (scanned from sibling files). Emits `package.xml` + a JSON rationale trail explaining why each item was included.
- **Verified working:** Given seed `CustomField Release_Signal__c.Status__c`, expands to 5 items — parent object, sibling field, validation rule referencing it, permission set granting access. Rationale trail names the specific reference in each source file.
- **If asked "what's the roadmap?":** See `docs/dep-resolver-architecture.md` — 5 phases from MVP (20 metadata types) to full parity with incumbents (~10 engineer-months for v1). The compare-two-orgs feature (Q3 in my roadmap) is the moment Gearset renewals stop.

---

## Part 3 — Failure modes we hit today (interview gold — proves iteration and problem-solving)

The interviewer will love hearing these — they show you don't just follow tutorials, you diagnose real errors.

### Failure 1: `TypeError: webidl.util.markAsUncloneable is not a function`
- **When:** During Authenticate Validation Org step, after sf CLI was successfully installed
- **Root cause:** Pinned base image was `node:20-slim`. sf CLI 2.143.6's transitive `undici` dependency requires the `webidl.util.markAsUncloneable` API which was added in Node.js 22.
- **Fix:** Bumped base image `node:20-slim` → `node:22-slim` across all step definitions in both pipelines (16 + 5 = 21 replacements). Node 22 is LTS as of 2024-10, safe pin.
- **What you learned:** Container image pinning surfaces dependency issues that developer laptops don't. In production, you'd bake a versioned custom image and pin at the image tag, not the base tag.

### Failure 2: `container has runAsNonRoot and image has non-numeric user (nginx), cannot verify user is non-root`
- **When:** DevOpsForce Site Deploy stage, pods failing to start
- **Root cause:** Kubernetes Pod Security admission enforces `runAsNonRoot` by checking the container image's declared user is a numeric UID. `nginx-unprivileged` image declares "nginx" (a name), which K8s can't resolve.
- **Fix:** Added `runAsUser: 101` + `runAsGroup: 101` to the pod template's `securityContext`. 101 is the canonical UID inside nginx-unprivileged.
- **What you learned:** Container image UID metadata vs. K8s admission checks are two different systems. The image can genuinely be non-root at runtime while still failing admission. Explicit numeric UIDs in the pod spec are the belt-and-suspenders fix.

### Failure 3: Modern Salesforce hides "New Connected App" creation
- **When:** Trying to follow the standard Salesforce Connected App JWT setup docs
- **Root cause:** Salesforce (2024+) removed the "New Connected App" button from Setup → App Manager for new orgs, forcing everyone to External Client Apps (ECAs) instead. Classic URLs like `/app/mgmt/newconnectedapp.apexp` are intercepted and redirect.
- **Fix:** Pivoted to External Client Apps. Functionally equivalent for JWT bearer flow — same Consumer Key, same certificate upload, same OAuth scope model. Only the UI wizard is different.
- **What you learned:** Every existing DevOps tool's Salesforce integration docs still say "Connected App." For new customers in modern orgs, the flow is subtly different. This is a documentation-update opportunity for Harness — first vendor to ship ECA-native SF setup docs wins onboarding time.

### Failure 4: Harness Free tier credit-card gate on Cloud runtime
- **When:** First attempt to run any pipeline with `runtime.type: Cloud`
- **Root cause:** Modern Harness Free tier requires sales-contact for CC validation; no self-serve UI to add a card. Pipeline `Initialize` step fails immediately.
- **Fix:** Retargeted both SF pipelines to `KubernetesDirect` infrastructure using the existing `gke_devopsforce` delegate. Same delegate the DevOpsForce Site pipeline uses. Bypasses the CC gate entirely because delegate-executed pipelines don't consume Harness Cloud credits.
- **What you learned:** Harness Free tier gates Cloud runtime behind sales, but delegate-executed pipelines are unrestricted. Real customers overwhelmingly use delegates anyway (they need to reach private resources); Cloud runtime is mainly for open-source and demo scenarios.

### Failure 5: Harness silently downscoped a Project connector to Project (not Account)
- **When:** Creating the GitHub connector inside the project context
- **Root cause:** The "URL Type: Account" field in the GitHub connector wizard refers to the GitHub URL layout (account URL vs repo URL), NOT the Harness connector scope. If you're inside a Project when creating a connector, Harness silently scopes it to that Project regardless of what you thought you selected.
- **Fix:** Made the SF pipeline's `codebase.connectorRef` a runtime input (`<+input>`) so it accepts any scope. Ultimately we resolved it since your `account.GitHub` connector exists and works.
- **What you learned:** UI terminology overload — "scope" is used for at least three different concepts in the Harness connector wizard. Clarifying the wizard's language would prevent 30 min of "why doesn't my connector work" debugging for every new customer.

---

## Part 4 — Likely interview questions and how to answer

Rehearse answers to these out loud. The panel WILL ask most of them.

**Q: Walk me through your DevOpsForce pipeline.**
→ "It's a two-stage CI/CD pipeline. Build stage runs on my GKE delegate, uses Harness's native Docker build-and-push step to build an nginx-based marketing site image, tags it with the pipeline run number, pushes to DockerHub. Deploy stage uses Harness's Kubernetes CD module — service definition pulls manifests from git, artifact from DockerHub, blue/green deploy with a templated HTTP health check between the color swap and traffic cutover. If the health check fails, rollback swaps back automatically. Green today."

**Q: Why blue/green vs canary vs rolling?**
→ (See Part 2 above — memorize the tradeoffs)

**Q: Tell me about the templatization you did.**
→ "The DevOpsForce pipeline uses a step template called `K8s_HTTP_Health_Check` v1 for the color-verify step. Reusable across any deployment pipeline that needs to hit an HTTP endpoint post-deploy and expect a specific status code. Runtime inputs for `HEALTH_URL` and `EXPECTED_STATUS`. If I extended the templatization work, I'd pull the `Install Salesforce CLI` step out of my Salesforce pipelines — it appears 5 times, that's the biggest duplication in my catalog right now."

**Q: What was the hardest thing you fixed?**
→ Pick ONE — I'd recommend the K8s runAsNonRoot fix because it demonstrates: reading pod events, understanding Pod Security admission, tracing "why is it still failing" to a state that was in code but never pushed to the right git repo. See Failure 2 in Part 3.

**Q: What would you do differently if starting over?**
→ "Bake sf CLI into a custom Docker image on day 1 instead of installing it per-stage — saves 60 seconds per stage in every pipeline run. Test JWT auth locally before wiring Harness — I hit `invalid assertion` errors that a local sanity test would have caught. And skip Playwright automation for Salesforce UI setup — turned out to be slower than clicking through manually because the SF UI changes too fast for stable selectors."

**Q: How would you support Salesforce customers on Harness?**
→ This is your differentiator. See `docs/product-brief.md`. Rough version:
"Salesforce DevOps is a ~$1B market. Harness's existing enterprise customers already pay Copado, Gearset, or Flosum for it. The wedge isn't new-customer acquisition — it's capturing that Salesforce spend from accounts that already trust Harness for the rest of their delivery pipeline. I built a working pipeline showing what Harness can do today, plus a metadata dependency-resolver stage showing the missing intelligence layer that Copado/Gearset differentiate on. The roadmap I'd propose is in the repo."

**Q: What's the Salesforce dep-resolver actually doing?**
→ (See Part 2, "Salesforce metadata dep-resolver" — and `docs/dep-resolver-architecture.md`)

**Q: You mentioned CI vs Custom Deployment Template — when would you pick each for Salesforce?**
→ "CI-based ships in a day and works out of the box using the same primitives Harness uses for everything else — Bash scripts in Run steps. Custom Deployment Template makes Salesforce a first-class deployable target in the CD module — you get Services, Environments, Rollback strategies natively. CI is the fast MVP; CDT is the correct long-term shape for enterprise customers who want Salesforce alongside their other CD targets under the same governance model. I built both in my account so I could talk to both patterns."

**Q: Why not use Harness Cloud (VMs) for the SF pipeline?**
→ "Free tier gates CC upgrade behind sales-contact. Delegate on my existing GKE cluster was zero-friction alternative and actually more realistic — enterprise customers overwhelmingly use delegates because they need to reach private Salesforce sandboxes behind IP allowlists that Harness Cloud can't."

**Q: How did you handle secrets?**
→ "All Salesforce auth material is stored in Harness Secrets in the `default_project`: 9 secrets total — client_id, username, base64-encoded JWT private key, one triple per role (validation/sandbox/prod). The pipeline injects them into steps via `<+secrets.getValue("...")>`. Private key is base64-encoded because Salesforce JWT auth needs the PEM as a file, but I want it stored as a text secret not a file secret — so the pipeline decodes at runtime into a workspace-local file at `.sf/ci/*.server.key` with chmod 600."

**Q: Show me the pipeline running.**
→ Run DevOpsForce Site — it's green. If they ask about SF, be honest: "I hit a JWT cert regeneration during hardening this week and I'd need 15 minutes to re-upload the cert to both orgs and update the Harness secrets before it runs. Let me instead show you the dep-resolver running locally against the same repo the pipeline would deploy — that's the intelligence layer that's the actual product thesis." Then run `bash scripts/run-resolver-demo.sh` — 1 seed → 5 items + rationale trail.

---

## Part 5 — What you honestly built vs. what you leaned on

Don't fake depth you don't have. The panel will spot it. Here's the honest framing for any question about YOUR role:

**On Kubernetes / GKE / Docker / Harness CI-CD lab:**
"I set up the GKE cluster and delegate following the Harness tutorial, adapted the standard nginx CI/CD example, and hit real production-shape problems — the runAsNonRoot admission rejection took me a couple iterations to diagnose. I'm not a Kubernetes veteran, but I now understand Pod Security admission, blue/green deployment mechanics, and how Harness's K8s CD module wires services and environments."

**On Salesforce:**
This is where you go deep. You're the expert. Own it fully. Speak to Gearset/Copado/Flosum architectures from your consulting experience, why metadata reference asymmetry is the hardest part of any real dep engine, the difference between Connected Apps and External Client Apps, the JWT bearer flow specifics. All of that is authentic to you.

**On product thinking:**
"I built the pipelines to demonstrate the platform, and then I wrote the product docs — dep-resolver architecture, 1-page product brief, build findings doc — because I wanted to think through what shipping a first-class Salesforce practice at Harness would actually look like. That's the role I'm ultimately interested in — Senior IE is the door in; leading the Salesforce practice is where I'd add the most leverage."

---

## Part 6 — Files to open live in the interview

If they let you screen-share, these are the highest-impact files to open in order:

1. **`.harness/salesforce-dx-governed-release.yaml`** — the 5-stage governed release pipeline. Scroll to the Approval stage to show the validation-evidence-embedded approval message.
2. **`.harness/feature-package-deploy.yaml`** — the dep-resolver-as-a-pipeline-stage. Scroll to the "Resolve Dependency Graph" step.
3. **`scripts/resolve-dependencies.py`** — the ~350-line stdlib-only Python resolver. Show the `forward_refs` + `inverse_refs` functions to demonstrate the asymmetric-reference insight.
4. **`docs/dep-resolver-architecture.md`** — the roadmap doc. Scroll to "What a Gearset-parity engine takes" table (person-months per component) and the 5-phase Harness product roadmap.
5. **`docs/product-brief.md`** — the 1-page GTM leave-behind. Read the "ask" paragraph at the end for the bigger-role framing.
6. **`docs/pipeline-build-findings.md`** — 17 findings + chronological decision log. Scroll to the "What Harness could ship" ranked list at the end.

Then **run the dep-resolver live** in the terminal: `bash scripts/run-resolver-demo.sh` — takes 3 seconds, produces the rationale trail output. That's the "wow" moment.

---

## Part 7 — Your ask, at the end of the interview

You're interviewing for Senior Implementation Engineer, but you have a bigger swing in mind. Rehearse this ask verbatim:

"I'm applying for Senior Implementation Engineer, and I'll do great work in that role — I want to earn my keep on customer implementations before proposing anything bigger. But I'd like to also talk with whoever owns Salesforce product strategy about how this thesis fits your roadmap. Whether that ends up being a Principal Customer Architect role, a founding position on a Salesforce practice, or a title that doesn't exist yet — I'd love the chance to make that case to the right person, either during this loop or in a follow-up. My repo is at github.com/joenormousman/Harness — everything I've built this week is there."

Don't apologize for the ambition. Don't hedge. Say it once, at the natural end of the conversation, and let them respond.

---

## Part 8 — What to review tonight

1. **Read this doc top to bottom** (~20 min)
2. **Read `docs/product-brief.md`** — you should be able to paraphrase the thesis without looking (~10 min)
3. **Read `docs/dep-resolver-architecture.md`** — you don't need to memorize the 5-phase roadmap, but know the person-month estimates for a real engine (~15 min)
4. **Run `bash scripts/run-resolver-demo.sh` yourself** — see the rationale trail output with your own eyes so you can describe what you'll show live (~2 min)
5. **Open the DevOpsForce Site pipeline in Harness** and click through each stage's steps once so you can describe them cold (~10 min)
6. **Sleep at a normal hour** — you know more than you think you do about the DevOps concepts, and every technical decision in this repo is defensible.

You built a lot this week. You're ready.
