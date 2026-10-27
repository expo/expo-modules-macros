#!/usr/bin/env node
'use strict';

// Scans a test module through the `expo-modules-macros` package in the given directory, as a project
// would. `getScannerBinaryPath()` must return the binary for this machine: `apple/ExpoModulesMacros`
// on macOS, and the one in the installed `@expo/modules-macros-<platform>-<arch>` package on Windows
// and Linux. `scanModules` must then report the module, and `expandMacros` must expand it. The Windows and Linux workflows run it with
// the binaries they build, and the Publish workflow with the release binaries before it publishes
// them.
//
// Usage: node scripts/check-scan.js <package-dir>

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const packageDir = process.argv[2];
if (!packageDir) {
  console.error('Usage: node scripts/check-scan.js <package-dir>');
  process.exit(2);
}

const expectedBinaryPath =
  process.platform === 'darwin'
    ? path.join('apple', 'ExpoModulesMacros')
    : path.join(
        'node_modules',
        '@expo',
        `modules-macros-${process.platform}-${process.arch}`,
        process.platform === 'win32' ? 'ExpoModulesMacros.exe' : 'ExpoModulesMacros'
      );

async function main() {
  const { expandMacros, getScannerBinaryPath, scanModules } = require(path.resolve(packageDir));
  const binaryPath = getScannerBinaryPath();
  if (!binaryPath.endsWith(expectedBinaryPath)) {
    throw new Error(`getScannerBinaryPath() returned ${binaryPath}, not a path ending in ${expectedBinaryPath}`);
  }
  console.log(`getScannerBinaryPath() returned ${binaryPath}`);

  const fixture = fs.mkdtempSync(path.join(os.tmpdir(), 'scan-check-'));
  try {
    const moduleFile = path.join(fixture, 'Module.swift');
    fs.writeFileSync(moduleFile, '@ExpoModule\npublic final class ScanCheckModule {}\n');
    const result = await scanModules([fixture], { timeout: 60_000 });
    const module = result.modules.find((candidate) => candidate.name === 'ScanCheckModule');
    if (!module) {
      throw new Error(`scanModules didn't report ScanCheckModule:\n${JSON.stringify(result, null, 2)}`);
    }
    console.log(`scanModules reported ${module.name} in ${module.file}`);

    const expanded = await expandMacros([moduleFile], { timeout: 60_000 });
    const source = expanded.files[0]?.expansions[0]?.source ?? '';
    if (!source.includes('_jsName = "ScanCheckModule"')) {
      throw new Error(`expandMacros didn't expand ScanCheckModule:\n${JSON.stringify(expanded, null, 2)}`);
    }
    console.log(`expandMacros expanded ${module.name}`);
  } finally {
    fs.rmSync(fixture, { recursive: true, force: true });
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
