#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const root = process.cwd();
const errors = [];

function readJson(relativePath) {
  const absolutePath = path.join(root, relativePath);
  try {
    return JSON.parse(fs.readFileSync(absolutePath, "utf8"));
  } catch (error) {
    errors.push(`${relativePath}: ${error.message}`);
    return null;
  }
}

function exists(relativePath) {
  if (!fs.existsSync(path.join(root, relativePath))) {
    errors.push(`${relativePath}: missing`);
  }
}

function read(relativePath) {
  try {
    return fs.readFileSync(path.join(root, relativePath), "utf8");
  } catch (error) {
    errors.push(`${relativePath}: ${error.message}`);
    return "";
  }
}

const project = readJson("sfdx-project.json");
if (project) {
  if (!Array.isArray(project.packageDirectories) || project.packageDirectories.length === 0) {
    errors.push("sfdx-project.json: packageDirectories must include at least one package directory");
  }

  if (!project.sourceApiVersion) {
    errors.push("sfdx-project.json: sourceApiVersion is required");
  }
}

const packageXml = read("manifest/package.xml");
if (!packageXml.includes("<Package xmlns=\"http://soap.sforce.com/2006/04/metadata\">")) {
  errors.push("manifest/package.xml: missing Salesforce metadata package namespace");
}

for (const className of ["HarnessReleaseHealth", "HarnessReleaseHealthTest"]) {
  exists(`force-app/main/default/classes/${className}.cls`);
  exists(`force-app/main/default/classes/${className}.cls-meta.xml`);
}

exists("force-app/main/default/permissionsets/Harness_Release_Observer.permissionset-meta.xml");

const sensitivePatterns = [
  /-----BEGIN (RSA |EC |)PRIVATE KEY-----/,
  /client_secret\s*[:=]/i,
  /password\s*[:=]\s*['"][^'"]+/i
];

const scanFiles = [
  "sfdx-project.json",
  "manifest/package.xml",
  "force-app/main/default/classes/HarnessReleaseHealth.cls",
  "force-app/main/default/classes/HarnessReleaseHealthTest.cls",
  "force-app/main/default/permissionsets/Harness_Release_Observer.permissionset-meta.xml"
];

for (const file of scanFiles) {
  const content = read(file);
  for (const pattern of sensitivePatterns) {
    if (pattern.test(content)) {
      errors.push(`${file}: possible secret material detected`);
    }
  }
}

if (errors.length > 0) {
  console.error("Salesforce project checks failed:");
  for (const error of errors) {
    console.error(`- ${error}`);
  }
  process.exit(1);
}

console.log("Salesforce project checks passed.");
