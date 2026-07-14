#!/usr/bin/env node
import fs from "node:fs";

const reportPath = process.argv[2];

if (!reportPath) {
  console.error("Usage: node scripts/extract-salesforce-deploy-result.mjs <deploy-result.json>");
  process.exit(2);
}

let payload;
try {
  payload = JSON.parse(fs.readFileSync(reportPath, "utf8"));
} catch (error) {
  console.error(`Unable to read Salesforce deploy report ${reportPath}: ${error.message}`);
  process.exit(1);
}

const result = payload.result ?? {};
const jobId = result.id ?? result.jobId ?? result.deployId ?? "";
const status = result.status ?? result.state ?? (payload.status === 0 ? "Succeeded" : "Unknown");
const checkOnly = String(result.checkOnly ?? result.dryRun ?? false);
const testsTotal = result.numberTestsTotal ?? result.details?.runTestResult?.numTestsRun ?? "";
const testsFailed = result.numberTestErrors ?? result.details?.runTestResult?.numFailures ?? "";

function quote(value) {
  return `'${String(value).replace(/'/g, "'\\''")}'`;
}

console.log(`export VALIDATION_JOB_ID=${quote(jobId)}`);
console.log(`export DEPLOY_JOB_ID=${quote(jobId)}`);
console.log(`export DEPLOY_STATUS=${quote(status)}`);
console.log(`export DEPLOY_CHECK_ONLY=${quote(checkOnly)}`);
console.log(`export DEPLOY_TESTS_TOTAL=${quote(testsTotal)}`);
console.log(`export DEPLOY_TESTS_FAILED=${quote(testsFailed)}`);
