# Interview Talk Track

## Opening

I built this as a Salesforce DX release pipeline in Harness because Salesforce sits directly in revenue operations, support workflows, renewals, and customer success. When its delivery process is under-supported, product teams inherit release risk that is hard to see until production is already affected.

## Architecture

The pipeline treats Salesforce metadata like production software:

- Source lives in Git in Salesforce DX format.
- Harness validates every change against a non-production org.
- Sandbox deployment proves the release in an org before production.
- Production is validated before approval.
- Production deploy uses quick deploy from the validated job ID.
- A post-deploy Apex smoke test verifies the release path.

## Why Harness

Harness is useful here because Salesforce delivery is not only a CLI problem. The product problem is governance, evidence, secret handling, reuse, and release visibility.

This demo uses:

- Harness pipeline-as-code for repeatability.
- Harness secrets for connected-app JWT credentials.
- Harness Cloud runners for isolated execution.
- Harness output variables to pass the production validation job ID.
- Harness approval stages to gate production release with validation evidence.

## Product Angle

If I were helping the product team build toward the future, I would look for where Salesforce users are still hand-assembling release workflows:

- Native Salesforce pipeline templates.
- Metadata diff rendering inside approval messages.
- Org topology modeling across dev, QA, UAT, staging, and production.
- Built-in support for unlocked package promotion.
- Safer destructive-change workflows.
- Release evidence that links Harness execution IDs to Salesforce deployment IDs and Apex test outcomes.

## Strong Close

The value is not just "Harness can run sf commands." The value is that Harness can make Salesforce delivery governable, reusable, observable, and productized for teams that depend on Salesforce but do not want every org release to become a custom CI/CD project.
