#!/usr/bin/env node
'use strict';

// Runs swift-format on the `.swift` files under the given paths, or under the current directory
// when no path is given, that Git tracks or doesn't ignore. swift-format reads `.swift-format` at
// the repository root. With `--lint` it checks the files without changing them and fails on any
// finding, as CI does.
//
// It runs the swift-format on PATH, or on macOS the one in the selected Xcode when there is none.
// CI builds the version that `.github/workflows/swift-format.yml` pins, which can format
// differently from the one in Xcode.
//
// Usage: node scripts/swift-format.js [--lint] [path ...]

const childProcess = require('node:child_process');
const fs = require('node:fs');

/**
 * Returns the command that runs swift-format.
 */
function swiftFormatCommand() {
  const { error } = childProcess.spawnSync('swift-format', ['--version'], { stdio: 'ignore' });
  if (error?.code === 'ENOENT' && process.platform === 'darwin') {
    return ['xcrun', 'swift-format'];
  }
  return ['swift-format'];
}

/**
 * Runs a command and returns its stdout. Throws when it can't start or exits with an error.
 */
function output(command, args) {
  const result = childProcess.spawnSync(command, args, { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
  if (result.error) {
    throw result.error;
  }
  if (result.status !== 0) {
    throw new Error(`\`${command} ${args.join(' ')}\` exited with code ${result.status}:\n${result.stderr}`);
  }
  return result.stdout;
}

function main() {
  const args = process.argv.slice(2);
  const lint = args.includes('--lint');
  const paths = args.filter((arg) => arg !== '--lint');

  // `--cached` also lists a tracked file that was deleted but not staged, and lists an unmerged file
  // once per stage.
  const listed = output('git', [
    'ls-files',
    '-z',
    '--cached',
    '--others',
    '--exclude-standard',
    '--',
    ...(paths.length > 0 ? paths : ['.']),
  ]);
  const files = [...new Set(listed.split('\0'))].filter((file) => file.endsWith('.swift') && fs.existsSync(file));
  if (files.length === 0) {
    return 0;
  }

  const [command, ...commandArgs] = swiftFormatCommand();
  const modeArgs = lint ? ['lint', '--strict'] : ['format', '--in-place'];
  const result = childProcess.spawnSync(command, [...commandArgs, ...modeArgs, '--parallel', ...files], {
    stdio: 'inherit',
  });
  if (result.error) {
    throw result.error;
  }
  return result.status ?? 1;
}

try {
  process.exitCode = main();
} catch (error) {
  console.error(error);
  process.exitCode = 1;
}
