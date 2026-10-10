#!/usr/bin/env node
'use strict';

// Sets the version of every package in `platforms/` to the version of `expo-modules-macros`, and
// lists them, with that exact version, as optional dependencies of `expo-modules-macros`. The
// Publish workflow runs it after the version bump, so the three packages always ship together.
//
// Usage: node scripts/set-platform-versions.js

const fs = require('node:fs');
const path = require('node:path');

const rootPackagePath = path.join(__dirname, '..', 'package.json');
const platformsDir = path.join(__dirname, '..', 'platforms');

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

function writeJson(filePath, value) {
  fs.writeFileSync(filePath, JSON.stringify(value, null, 2) + '\n');
}

const rootPackage = readJson(rootPackagePath);
const version = rootPackage.version;
const optionalDependencies = {};

for (const entry of fs.readdirSync(platformsDir, { withFileTypes: true })) {
  if (!entry.isDirectory()) {
    continue;
  }
  const packagePath = path.join(platformsDir, entry.name, 'package.json');
  const platformPackage = readJson(packagePath);
  platformPackage.version = version;
  writeJson(packagePath, platformPackage);
  optionalDependencies[platformPackage.name] = version;
  console.log(`${platformPackage.name}@${version}`);
}

rootPackage.optionalDependencies = optionalDependencies;
writeJson(rootPackagePath, rootPackage);
