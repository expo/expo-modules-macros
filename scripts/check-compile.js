#!/usr/bin/env node
'use strict';
// Compiles the macro expansions of the fixtures in `scripts/check-compile` with `swiftc` and the given
// macro plugin, and runs them. The expansion tests compare text, so they don't catch generated code
// that doesn't compile, or that compiles only in some build settings. This builds the stand-in core
// module of `Core.swift` with library evolution, then, in each configuration of `CONFIGURATIONS`:
//
// - builds `Props.swift`, `Views.swift`, `SharedObjects.swift` and `JSClasses.swift` as a library, with no warnings
//   allowed;
// - with library evolution, also verifies its `.swiftinterface` and builds `Client.swift` from it;
// - builds the same files and `main.swift` as an executable and runs it, which checks the decoded and reset
//   values, the views, and the JavaScript class chain of the shared objects and the JavaScript classes.
//
// It also type-checks `JSClassErrors.swift` once and expects an error on each line after an `expect-error`
// comment.
//
// It runs on macOS. The macOS workflow runs it with the debug tool that `swift test` builds, during
// the release build.
//
// Usage: node scripts/check-compile.js <binary>
//
// For example `node scripts/check-compile.js .build/debug/ExpoModulesMacrosTool` after `swift build`.
const childProcess = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const [binaryArgument] = process.argv.slice(2);
if (!binaryArgument) {
  console.error('Usage: node scripts/check-compile.js <binary>');
  process.exit(2);
}
if (process.platform !== 'darwin') {
  console.error('check-compile.js runs only on macOS');
  process.exit(2);
}

const fixturesDirectory = path.join(__dirname, 'check-compile');

// The module of `Props.swift`, `Views.swift`, `SharedObjects.swift` and `JSClasses.swift`. Its name differs from
// every type and member name in the fixtures: a `.swiftinterface` of Swift 6.3 or older qualifies a type with the
// module name, so for a module named `Props` the `Props` typealias of an `@ExpoView` view reads
// `Props.PublicProps`, where `Props` is the typealias itself.
const LIBRARY_MODULE = 'Fixtures';
const plugin = `${path.resolve(binaryArgument)}#ExpoModulesMacros`;

// The upcoming features that ExpoModulesJSI builds with, also used by apps that build with Xcode's
// "Approachable Concurrency" setting.
const UPCOMING_FEATURES = [
  '-enable-upcoming-feature',
  'NonisolatedNonsendingByDefault',
  '-enable-upcoming-feature',
  'InferIsolatedConformances',
];

const CONFIGURATIONS = [
  { name: 'no default isolation', flags: [] },
  { name: 'library evolution', flags: ['-enable-library-evolution'], libraryEvolution: true },
  { name: 'default isolation MainActor', flags: ['-default-isolation', 'MainActor', ...UPCOMING_FEATURES] },
];

function fixture(file) {
  return path.join(fixturesDirectory, file);
}

// Runs `swiftc` with the given arguments and throws with its output when it fails.
function swiftc(args) {
  const result = childProcess.spawnSync('swiftc', ['-swift-version', '6', ...args], { encoding: 'utf8' });
  if (result.error) {
    throw result.error;
  }
  if (result.status !== 0) {
    throw new Error(`swiftc failed:\n${result.stdout}${result.stderr}`);
  }
}

function buildCore(directory) {
  swiftc([
    '-parse-as-library',
    '-enable-library-evolution',
    ...UPCOMING_FEATURES,
    '-load-plugin-executable',
    plugin,
    '-emit-library',
    '-emit-module',
    '-module-name',
    'Core',
    '-emit-module-path',
    path.join(directory, 'Core.swiftmodule'),
    '-o',
    path.join(directory, 'libCore.dylib'),
    '-Xlinker',
    '-install_name',
    '-Xlinker',
    '@rpath/libCore.dylib',
    fixture('Core.swift'),
  ]);
}

function check(configuration, coreDirectory, directory) {
  const libraryDirectory = path.join(directory, 'library');
  const interfaceDirectory = path.join(directory, 'interface');
  fs.mkdirSync(libraryDirectory);
  fs.mkdirSync(interfaceDirectory);
  const common = [
    ...configuration.flags,
    '-warnings-as-errors',
    '-load-plugin-executable',
    plugin,
    '-I',
    coreDirectory,
    '-L',
    coreDirectory,
    '-lCore',
  ];

  const interfacePath = path.join(interfaceDirectory, `${LIBRARY_MODULE}.swiftinterface`);
  const interfaceFlags = configuration.libraryEvolution
    ? ['-emit-module-interface-path', interfacePath, '-verify-emitted-module-interface']
    : [];
  swiftc([
    ...common,
    '-parse-as-library',
    '-emit-library',
    '-emit-module',
    '-module-name',
    LIBRARY_MODULE,
    '-emit-module-path',
    path.join(libraryDirectory, `${LIBRARY_MODULE}.swiftmodule`),
    ...interfaceFlags,
    '-o',
    path.join(libraryDirectory, `lib${LIBRARY_MODULE}.dylib`),
    fixture('Props.swift'),
    fixture('Views.swift'),
    fixture('SharedObjects.swift'),
    fixture('JSClasses.swift'),
  ]);
  console.log(`  built Props.swift, Views.swift, SharedObjects.swift and JSClasses.swift as a library`);

  if (configuration.libraryEvolution) {
    // The interface directory has no binary module, so `import Fixtures` builds the module from the
    // interface, as for a prebuilt package.
    swiftc([
      ...common,
      '-parse-as-library',
      '-I',
      interfaceDirectory,
      '-L',
      libraryDirectory,
      `-l${LIBRARY_MODULE}`,
      '-emit-library',
      '-module-name',
      'Client',
      '-o',
      path.join(directory, 'libClient.dylib'),
      fixture('Client.swift'),
    ]);
    console.log(`  built Client.swift from ${LIBRARY_MODULE}.swiftinterface`);
  }

  const executable = path.join(directory, 'check');
  swiftc([
    ...common,
    '-Xlinker',
    '-rpath',
    '-Xlinker',
    coreDirectory,
    '-module-name',
    'Checks',
    '-o',
    executable,
    fixture('Props.swift'),
    fixture('Views.swift'),
    fixture('SharedObjects.swift'),
    fixture('JSClasses.swift'),
    fixture('main.swift'),
  ]);
  const result = childProcess.spawnSync(executable, { encoding: 'utf8' });
  if (result.error) {
    throw result.error;
  }
  if (result.status !== 0) {
    throw new Error(`The checks of main.swift failed:\n${result.stdout}${result.stderr}`);
  }
  console.log(`  ran main.swift: ${result.stdout.trim()}`);
}

// Type-checks `JSClassErrors.swift`, which must fail with an error on each line after an `// expect-error` line
// and on no other line. An error in another file, such as the code that a macro generates, fails the check too.
// The macro reports these errors from the conformances that the compiler passes, so only the compiler can show
// them.
function checkExpectedErrors(coreDirectory) {
  const file = fixture('JSClassErrors.swift');
  const expected = fs
    .readFileSync(file, 'utf8')
    .split('\n')
    .flatMap((line, index) => (line.trim() === '// expect-error' ? [index + 2] : []));
  const result = childProcess.spawnSync(
    'swiftc',
    [
      '-swift-version',
      '6',
      '-parse-as-library',
      '-typecheck',
      '-load-plugin-executable',
      plugin,
      '-I',
      coreDirectory,
      file,
    ],
    { encoding: 'utf8' }
  );
  if (result.error) {
    throw result.error;
  }
  const output = `${result.stdout}${result.stderr}`;
  // The location of each error, as `<file>:<line>:<column>: error:` at the start of a line.
  const errors = [...output.matchAll(/^(.+?):(\d+):\d+: error:/gm)];
  const reported = [...new Set(errors.filter((match) => match[1] === file).map((match) => Number(match[2])))];
  const elsewhere = errors.filter((match) => match[1] !== file).map((match) => `${match[1]}:${match[2]}`);
  if (result.status === 0 || elsewhere.length > 0 || reported.join(',') !== expected.join(',')) {
    throw new Error(
      `JSClassErrors.swift reported errors on lines [${reported}], not [${expected}], and in other files ` +
        `[${elsewhere}]:\n${output}`
    );
  }
  console.log(`type-checked JSClassErrors.swift: errors on lines ${expected.join(', ')}, as expected`);
}

const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'check-compile-'));
try {
  const coreDirectory = path.join(directory, 'core');
  fs.mkdirSync(coreDirectory);
  buildCore(coreDirectory);
  // Each check runs, also after one fails, so that the output shows every failing one.
  const failed = [];
  try {
    checkExpectedErrors(coreDirectory);
  } catch (error) {
    console.error(error.message);
    failed.push('JSClassErrors.swift');
  }
  for (const configuration of CONFIGURATIONS) {
    console.log(`${configuration.name}:`);
    const configurationDirectory = path.join(directory, configuration.name.replaceAll(' ', '-'));
    fs.mkdirSync(configurationDirectory);
    try {
      check(configuration, coreDirectory, configurationDirectory);
    } catch (error) {
      console.error(error.message);
      failed.push(configuration.name);
    }
  }
  if (failed.length > 0) {
    throw new Error(`Failed with ${failed.join(', ')}`);
  }
  console.log('The expansions compile and run in each configuration');
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
} finally {
  fs.rmSync(directory, { recursive: true, force: true });
}
