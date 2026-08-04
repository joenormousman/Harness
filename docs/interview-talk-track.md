# Interview Talk Track

**Use this as the shape of what you say — not a memorized script.** Sequence assumes a technical interview where you get 30-45 minutes to walk through what you built and why. Adjust for the room's tempo.

---

## Opening (60 seconds)

*"This week I built two things in Harness, both tied to the DevOps practice I want to help Harness ship. The first is a working Kubernetes CI/CD pipeline — DevOpsForce Site — that builds an nginx image, pushes to DockerHub, and blue/green deploys to my GKE cluster via a self-hosted delegate. Green today. That's my proof I can execute on the Harness lab pattern.*

*The second is a Salesforce DX release pipeline plus a metadata dependency-resolver that runs in Harness. I brought years of Salesforce DevOps experience — architecting Copado, Gearset, and Flosum pipelines for customers — and I wanted to show what Harness could ship in that space that would displace those incumbents from Harness's own existing enterprise customers. That's the wedge I want to build inside Harness."*

---

## Part 1 — Walk through DevOpsForce Site (the green pipeline)

*"Two stages, both running on my GKE cluster via a Harness delegate installed in the `harness-build` namespace."*

### Build stage
- **Sanity check** — small alpine container verifies the site index exists and contains the expected content. Fast-fails before spending time on an image build.
- **Build and push** — Harness's native Docker step. Builds the Dockerfile at repo root, passes the pipeline sequence ID as a `BUILD_TAG` build-arg, tags the image both with that ID and `latest`, pushes to DockerHub via the DockerHub connector. The build-arg matters — it's sed'd into `index.html` so I can visually confirm which build is serving traffic in the browser.

### Deploy stage
- Harness Kubernetes CD module. Service definition pulls K8s manifests from the same DevOpsForce git repo, artifact from DockerHub, environment is `Prod`, infrastructure targets the `devopsforce` namespace.
- **Blue/Green deploy** — new version comes up as a stage deployment alongside the currently-serving primary. Both are live K8s Deployments; only primary receives user traffic. Two services exist: one selects primary, one selects stage.
- **Health check** — invokes a reusable step template called `K8s_HTTP_Health_Check` v1. Hits the stage service inside the cluster on `/healthz`, expects HTTP 200. Real user traffic never touches the new version until this passes. *This is my templatization story too — the lab bonus item is already in production in this pipeline.*
- **Swap** — `K8sBGSwapServices` flips the service selectors. Atomic traffic cutover; no half-and-half window.
- **Rollback** — if any step fails, the rollback step swaps back to the previous primary. Instant, no re-deploy needed. Wired via `failureStrategies: onFailure: StageRollback`.

### Container/pod details worth mentioning
- Base image is `nginxinc/nginx-unprivileged` — non-root out of the box, listens on port 8080 because unprivileged containers can't bind below 1024. Service maps 80→8080.
- Pod securityContext sets `runAsUser: 101` explicitly — this bit me during the lab. GKE Pod Security admission needs a *numeric* UID to verify non-root; the image's declared user "nginx" (a name) can't be resolved by admission without running the container.

---

## Part 2 — The Salesforce work (your differentiator)

*"Now what I really wanted to build here was a Salesforce release pipeline in Harness, because Salesforce DevOps is where I've done most of my architecture work — Gearset, Copado, Flosum. It's a big market, and Harness's existing enterprise customers are already paying money for it, they just aren't paying it to Harness."*

### The pipeline I built
- **5-stage governed release**: Validate PR → Deploy Sandbox → Validate Production → **Approve Production** (with the validation status and job ID embedded in the approval message) → **Quick Deploy Production** (uses the pre-validated job ID so Salesforce skips the test re-run).
- **JWT bearer flow** for non-interactive auth. Salesforce's industry-standard pattern — a self-signed cert per org uploaded to an External Client App, private key stored as a base64 Harness secret, pipeline signs a JWT at runtime.
- **Runs on the same delegate** as the DevOpsForce pipeline. Originally targeted Harness Cloud runners; Free tier gates that behind sales-contact, and delegates are how real enterprise customers deploy anyway (they need to reach private sandboxes behind IP allowlists that Harness Cloud can't).

### Current honest state
*"The pipeline is imported into Harness, all 5 stages render, retargeted to my delegate infrastructure. Auth is where it stops today — I hit `invalid_assertion` at the JWT bearer step, regenerated the cert to eliminate crypto doubt, but I haven't yet re-uploaded the new cert to both orgs and updated the Harness secrets. About 15 minutes of setup work. Not a design issue; a certificate propagation task I didn't finish."*

### The dep-resolver (this is the real product play)
*"What I want to show you actually running is the metadata dependency resolver. This is my thesis for what Harness should ship that would let it displace Gearset."*

- **The problem:** Salesforce metadata references are asymmetric. A ValidationRule knows the fields its formula uses. A CustomField doesn't know which ValidationRules or PermissionSets reference it. So "deploy just this one field" fails or leaves the target org broken unless something scans sibling files.
- **What I built:** ~350 lines of Python, stdlib only. Handles 5 metadata types (CustomObject, CustomField, ValidationRule, PermissionSet, Profile), both directions of the reference walk, emits a `package.xml` plus a JSON rationale trail explaining why each item was included. Wired into a second Harness pipeline that reads a seed manifest, expands it via the resolver, and deploys the resolved subset via `sf project deploy start --manifest`.
- **Live demo:** Give it a single-field seed. Resolver expands to 5 items — parent object, sibling field the validation rule also references, the validation rule itself, and the permission set that grants access to both fields. Each with a rationale line pointing at the specific reference in the specific file.
- **Why this matters commercially:** This dependency-aware packaging is the exact intelligence layer Gearset, Copado, and Flosum charge for. In `docs/dep-resolver-architecture.md` I sketched what a real production-grade engine would take (~10 engineer-months for v1, ~12-18 months for parity), and a 5-phase Harness product roadmap. Q3 of that roadmap — cross-org compare-and-suggest — is where Gearset renewals stop.

---

## Part 3 — Why Harness for Salesforce

*"Salesforce delivery isn't only a CLI problem. The product problem is governance, evidence, secret handling, reuse, and release visibility. Harness already has all of those primitives shipping in production for every other CD target."*

What my SF pipeline uses that's already Harness-native:
- Pipeline-as-code stored in git, versioned alongside the metadata itself.
- Secrets manager for JWT credentials — no keys checked into repos.
- **Human approval stage** with the production validation status and job ID embedded in the approval message. That's the exact "release evidence" pattern Copado charges enterprise-tier prices to replicate.
- **Output variables** to pass the pre-validated deploy job ID from the validate stage to the quick-deploy stage — that's how the pipeline skips redundant test runs during production release.
- Same delegate model as every other Harness deployment target — customers already know how to operate it.

*"The gap isn't in Harness's platform capabilities. The gap is that the Salesforce integration today is basically `sf` CLI wrapped in Bash. It works for pro-code developers. It doesn't work for admin-developers — who are the majority of Salesforce change-makers — and it doesn't have the dependency intelligence that Gearset built its business on."*

---

## Part 4 — The product angle (what Harness could ship)

Where I'd invest, ordered by hours-saved-per-hour-of-Harness-eng-work (full detail in `docs/product-brief.md` and `docs/dep-resolver-architecture.md`):

- **First-class Salesforce Connected/External Client App setup wizard** in the Harness UI. Removes the biggest first-hour friction for any customer trying Harness for Salesforce. Days of eng work; unblocks admin-developer adoption at every customer site.
- **Metadata dependency-aware packaging** as a first-class pipeline capability — the resolver work I prototyped this week, hardened to production coverage.
- **Cross-org compare-and-suggest** as an admin-developer-facing UI: "you changed these 3 items in dev; here's the resolved package we'd promote." This is where Gearset renewals stop.
- **Metadata diff rendering inside Harness approval messages** so release managers can see exactly what's shipping without leaving Harness.
- **Native org-topology modeling** — dev/QA/UAT/staging/production as first-class Harness Environments — with Salesforce-specific promotion policies (destructive-change safety, permission-set diff, profile-vs-permset preferences).
- **Salesforce Package Deploy as a Custom Deployment Template** in the CD module (alongside Kubernetes, ECS, etc.) so Salesforce sits as a peer with the other deploy targets under the same governance model, not as an odd-shaped CI use case.
- **AIDA-assisted seed-manifest generation** — "given this Jira ticket, suggest the metadata package." This is where Harness's existing AI investment meets the Salesforce gap.

---

## Strong close (30 seconds)

*"The value isn't just 'Harness can run `sf` commands.' That's what Harness has today and it's the correct MVP. The value is that Harness can make Salesforce delivery **governable, auditable, admin-developer-safe, and dependency-aware** — the four things Gearset and Copado sell for enterprise-tier prices. And Harness has an unfair advantage on the go-to-market: your customer accounts already have contracts, procurement approval, and security review cleared. Landing a Salesforce practice inside those accounts is a quarters-to-months cycle, not multi-year.*

*I'd love to help build that. I'm applying for Senior Implementation Engineer as the door in, but if there's an appetite for someone to help scope and lead the Salesforce practice from the inside, I want to make that case to whoever owns the decision — either during this loop or in a follow-up. Everything I built this week is at github.com/joenormousman/Harness."*
