#!/usr/bin/env node
'use strict';

// Scans test modules through the `expo-modules-macros` package in the given directory, as a project
// would. `getScannerBinaryPath()` must return the binary for this machine: `apple/ExpoModulesMacros`
// on macOS, and the one in the installed `@expo/modules-macros-<platform>-<arch>` package on Windows
// and Linux. `scanModules` must then report a module, `expandMacros` must expand it, and
// `scanExports` must report the surface in `check-scan-exports.json` for `EXPORTS_FIXTURE`, the same
// on every platform. The macOS, Windows and Linux workflows run it with the binaries they build, and
// the Publish workflow with the release binaries before it publishes them.
//
// Usage: node scripts/check-scan.js <package-dir>
//        node scripts/check-scan.js <package-dir> --update <binary>
//
// With `--update`, it only scans `EXPORTS_FIXTURE` with the given binary, for example
// `.build/debug/ExpoModulesMacrosTool`, and writes the result to `check-scan-exports.json`.

const assert = require('node:assert');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const [packageDir, updateFlag, updateBinaryPath] = process.argv.slice(2);
if (!packageDir || (updateFlag !== undefined && (updateFlag !== '--update' || !updateBinaryPath))) {
  console.error('Usage: node scripts/check-scan.js <package-dir> [--update <binary>]');
  process.exit(2);
}

const expectedExportsPath = path.join(__dirname, 'check-scan-exports.json');

// Declarations of each kind that `scan-exports` reports, in two files, one of them in a
// subdirectory. `Types/Models.swift` has CRLF line endings, as a Windows checkout can have, and a
// non-ASCII string, which the scanner must pass through stdout unchanged.
const EXPORTS_FIXTURE = {
  'PlayerModule.swift': {
    lineEnding: '\n',
    source: `import ExpoModulesCore

@ExpoModule("ScanCheckPlayer", classes: [Player.self])
public final class PlayerModule {
  @JS
  func greet(_ name: String, punctuation: String = "!") -> String {
    name + punctuation
  }

  @JS("loadAsync")
  func load(source: Source, options: LoadOptions?) async throws -> [String: Double] {
    [:]
  }

  @JS
  var volume: Double = 1.0

  @JS
  var version: String { "1.0" }

  @Event
  var onStatusChange: (Status) -> Void

  @Event(.inline)
  var onTick: () -> Void

  #if os(iOS)
    @Event
    var onPictureInPictureChange: (Bool) -> Void
  #endif

  @available(iOS 17.0, *)
  @JS
  func newerFeature() -> Bool { true }
}

@SharedObject
public final class Player: SharedRef<Data> {
  @JS
  init(url: String) {}

  @JS
  func play(at time: Double = 0) {}

  @JS
  static func supportedFormats() -> [String] { [] }
}
`,
  },
  'Types/Models.swift': {
    lineEnding: '\r\n',
    source: `@Record
struct LoadOptions {
  var title: String = "Zażółć gęślą jaźń"
  var retries: Int = 3
  var headers: [String: String]?
  var startAt: Double
}

enum Status: String, Enumerable {
  case idle
  case playing = "play"
  #if os(iOS) || os(visionOS)
    case pictureInPicture
  #endif
}

enum Quality: Int, Enumerable {
  case low = 1
  case high
}

@Union
enum Source {
  case url(String)
  case options(LoadOptions)
}
`,
  },
};

const expectedBinaryPath =
  process.platform === 'darwin'
    ? path.join('apple', 'ExpoModulesMacros')
    : path.join(
        'node_modules',
        '@expo',
        `modules-macros-${process.platform}-${process.arch}`,
        process.platform === 'win32' ? 'ExpoModulesMacros.exe' : 'ExpoModulesMacros'
      );

function writeExportsFixture(directory) {
  for (const [file, { lineEnding, source }] of Object.entries(EXPORTS_FIXTURE)) {
    const filePath = path.join(directory, ...file.split('/'));
    fs.mkdirSync(path.dirname(filePath), { recursive: true });
    fs.writeFileSync(filePath, source.replaceAll('\n', lineEnding));
  }
}

// Returns the `scanExports` result without what differs between machines: the absolute paths of
// the files, which become relative to `directory` with `/` separators, and the scan duration.
function portableExports(result, directory) {
  const marker = `/${path.basename(directory)}/`;
  const exports = structuredClone(result.exports);
  for (const declarations of Object.values(exports)) {
    for (const declaration of declarations) {
      const normalized = declaration.file.replaceAll('\\', '/');
      const index = normalized.lastIndexOf(marker);
      if (!path.isAbsolute(declaration.file) || index < 0) {
        throw new Error(`scanExports reported ${declaration.file}, not an absolute path in ${directory}`);
      }
      declaration.file = normalized.slice(index + marker.length);
    }
  }
  return {
    exports,
    filesScanned: result.stats.filesScanned,
    filesParsed: result.stats.filesParsed,
  };
}

async function scanExportsFixture(scanExports, binaryPath) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'scan-exports-check-'));
  try {
    writeExportsFixture(directory);
    const result = await scanExports([directory], { binaryPath, timeout: 60_000 });
    return portableExports(result, directory);
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
}

async function update(scanExports) {
  const actual = await scanExportsFixture(scanExports, path.resolve(updateBinaryPath));
  fs.writeFileSync(expectedExportsPath, `${JSON.stringify(actual, null, 2)}\n`);
  console.log(`Wrote ${expectedExportsPath}`);
}

async function check({ expandMacros, getScannerBinaryPath, scanExports, scanModules }) {
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

  const actual = await scanExportsFixture(scanExports);
  const expected = JSON.parse(fs.readFileSync(expectedExportsPath, 'utf8'));
  assert.deepStrictEqual(
    actual,
    expected,
    `scanExports reported a different surface than ${path.basename(expectedExportsPath)}. When the change is ` +
      'intended, update it with `node scripts/check-scan.js . --update <binary>`.'
  );
  const { exports } = actual;
  const counts = Object.entries(exports).map(([kind, declarations]) => `${declarations.length} ${kind}`);
  console.log(`scanExports reported ${counts.join(', ')}, as ${path.basename(expectedExportsPath)} expects`);
}

async function main() {
  const wrapper = require(path.resolve(packageDir));
  if (updateFlag) {
    await update(wrapper.scanExports);
  } else {
    await check(wrapper);
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
