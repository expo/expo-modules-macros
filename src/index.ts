import { execFile } from 'node:child_process';
import path from 'node:path';

import {
  ScanExportsResult,
  ScanModulesResult,
  SUPPORTED_SCAN_EXPORTS_SCHEMA_VERSION,
  SUPPORTED_SCAN_MODULES_SCHEMA_VERSION,
} from './types';

export * from './types';

/** Options accepted by `scanModules`, mirroring the CLI's `scan-modules` flags. */
export interface ScanModulesOptions {
  /** Conditional compilation flags to treat as set, e.g. `['DEBUG']`. */
  defines?: string[];

  /** Overrides the scanner binary path. Defaults to the one shipped with this package. */
  binaryPath?: string;

  /** Milliseconds after which the scanner is killed and the scan fails. No limit by default. */
  timeout?: number;
}

/**
 * Options accepted by `scanExports`. The deep scan evaluates `#if` per platform with no flags set, so
 * it takes no define option.
 */
export interface ScanExportsOptions {
  /** Overrides the scanner binary path. Defaults to the one shipped with this package. */
  binaryPath?: string;

  /** Milliseconds after which the scanner is killed and the scan fails. No limit by default. */
  timeout?: number;
}

/**
 * Thrown when the scanner exits non-zero. Exit code 2 is a usage error (bad subcommand or flags) and
 * 1 means the report couldn't be encoded; both put a message on stderr, carried here as `stderr`.
 */
export class ScannerError extends Error {
  constructor(
    message: string,
    readonly exitCode: number | null,
    readonly stderr: string
  ) {
    super(message);
    this.name = 'ScannerError';
  }
}

/** Thrown when the binary's output schema doesn't match what these types were written against. */
export class ScannerSchemaVersionError extends Error {
  constructor(
    readonly command: string,
    readonly found: number,
    readonly expected: number
  ) {
    super(
      `\`${command}\` returned schema version ${found}, but this package understands ${expected}. ` +
        'The scanner binary and this wrapper are out of sync; align their versions.'
    );
    this.name = 'ScannerSchemaVersionError';
  }
}

/**
 * The platforms whose binaries ship in packages of their own, one per architecture, with the
 * machines that those packages install on.
 */
const platformPackageMachines: Partial<Record<NodeJS.Platform, string>> = {
  win32: 'Windows x64 and arm64',
  linux: 'Linux x64 and arm64 with glibc',
};

/**
 * The package with the binary for the current platform and architecture, for example
 * `@expo/modules-macros-win32-x64` or `@expo/modules-macros-linux-arm64`. It is an optional
 * dependency of this package, and its `os`, `cpu` and (on Linux) `libc` fields make package managers
 * install it only on a matching machine.
 */
function platformBinaryPackageName(): string {
  return `@expo/modules-macros-${process.platform}-${process.arch}`;
}

/**
 * Absolute path to the scanner binary for the current platform. It doubles as the macro plugin
 * executable.
 *
 * - macOS: the universal binary shipped in this package, next to the Swift package rather than in a
 *   `bin` directory.
 * - Windows and Linux: `ExpoModulesMacros.exe` or `ExpoModulesMacros` from the package for the
 *   current platform and architecture (see `platformBinaryPackageName`). When that package isn't
 *   installed, for example in this repository, it falls back to the executable that `npm run build`
 *   writes to `platforms/<platform>-<arch>`.
 *
 * The path isn't checked here; running a missing binary fails with a `ScannerError` that says how to
 * get it.
 */
export function getScannerBinaryPath(): string {
  if (process.platform === 'darwin') {
    return path.join(__dirname, '..', 'apple', 'ExpoModulesMacros');
  }
  const fileName = process.platform === 'win32' ? 'ExpoModulesMacros.exe' : 'ExpoModulesMacros';
  try {
    const packageJson = require.resolve(`${platformBinaryPackageName()}/package.json`);
    return path.join(path.dirname(packageJson), fileName);
  } catch {
    return path.join(__dirname, '..', 'platforms', `${process.platform}-${process.arch}`, fileName);
  }
}

/** The message for a scanner binary that doesn't exist at `binaryPath`. */
function missingBinaryMessage(binaryPath: string): string {
  if (process.platform === 'darwin') {
    return `The scanner binary is missing at ${binaryPath}. Run \`npm run build\` in this package to build it.`;
  }
  const machines = platformPackageMachines[process.platform];
  if (machines === undefined) {
    return `The scanner binary is missing at ${binaryPath}. No binary is built for ${process.platform}.`;
  }
  return (
    `The scanner binary is missing at ${binaryPath}. It comes from the optional package ` +
    `${platformBinaryPackageName()}, which your package manager installs only on ${machines}. ` +
    'Reinstall dependencies without skipping optional ones (for example without `--omit=optional`), ' +
    'or run `npm run build` in this package to build it locally.'
  );
}

/**
 * Runs a scanner subcommand and parses its JSON report.
 *
 * Paths are passed after the options. The CLI has no `--` separator, so a path spelled exactly
 * `--define` would be read as that option instead; such a path isn't representable and the scan
 * fails with a usage error rather than scanning the wrong thing. `-h`/`--help` are worse, since the
 * CLI answers them from anywhere in argv by printing usage and exiting 0, which would surface as an
 * opaque parse failure. `assertRepresentablePaths` rejects those before spawning.
 *
 * Output is buffered rather than streamed: the report is only usable once complete. Scanning all of
 * `expo/packages` produces ~17 KB, so the raised `maxBuffer` is headroom for a far larger tree
 * rather than a limit anything is expected to approach.
 */
/**
 * Rejects paths the CLI can't receive as paths. `-h`/`--help` are recognized anywhere in argv, so
 * passing one as a path prints usage and exits 0: the scan never runs, and without this the caller
 * would see a JSON parse failure pointing at the wrong cause.
 */
function assertRepresentablePaths(command: string, paths: string[]): void {
  const helpFlag = paths.find((candidate) => candidate === '-h' || candidate === '--help');
  if (helpFlag !== undefined) {
    throw new TypeError(
      `${command} cannot scan a path named \`${helpFlag}\`: the scanner reads it as a help ` +
        'request. Pass a path that resolves to the same file, such as `./' +
        helpFlag +
        '`.'
    );
  }
}

function runScanner<T>(binaryPath: string, args: string[], timeout = 0): Promise<T> {
  // The error messages name only the subcommand: the paths can be hundreds of package roots.
  const command = `${path.basename(binaryPath)} ${args[0]}`;
  return new Promise((resolve, reject) => {
    const child = execFile(
      binaryPath,
      args,
      { maxBuffer: 64 * 1024 * 1024, encoding: 'utf8', timeout },
      (error, stdout, stderr) => {
        if (error) {
          // A spawn failure reports a string `code` (e.g. 'ENOENT'); a non-zero exit reports a
          // number. Only the latter is an exit status.
          const exitCode = typeof error.code === 'number' ? error.code : null;
          if (error.code === 'ENOENT') {
            reject(
              new ScannerError(
                missingBinaryMessage(binaryPath),
                null,
                stderr
              )
            );
            return;
          }
          if (timeout > 0 && error.killed) {
            reject(new ScannerError(`\`${command}\` timed out after ${timeout} ms.`, null, stderr));
            return;
          }
          reject(
            new ScannerError(
              `\`${command}\` failed: ${stderr.trim() || error.message}`,
              exitCode,
              stderr
            )
          );
          return;
        }

        try {
          resolve(JSON.parse(stdout) as T);
        } catch (parseError) {
          reject(
            new ScannerError(
              `Could not parse the scanner's JSON output: ${(parseError as Error).message}`,
              null,
              stderr
            )
          );
        }
      }
    );
    // The scanner never reads stdin. An executable without the scanner CLI would start the macro
    // plugin server instead and wait on stdin forever.
    child.stdin?.end();
  });
}

/**
 * Fast scan for top-level `@ExpoModule` types, for autolinking. Each path is a `.swift` file or a
 * directory, scanned recursively.
 *
 * Conditions the scan can't answer statically come back in `warnings` rather than throwing, so the
 * caller can surface them alongside its own diagnostics.
 */
export async function scanModules(
  paths: string[],
  options: ScanModulesOptions = {}
): Promise<ScanModulesResult> {
  if (paths.length === 0) {
    throw new TypeError('scanModules requires at least one path');
  }
  assertRepresentablePaths('scanModules', paths);

  const args = ['scan-modules'];
  for (const define of options.defines ?? []) {
    args.push('--define', define);
  }
  args.push(...paths);

  const result = await runScanner<ScanModulesResult>(
    options.binaryPath ?? getScannerBinaryPath(),
    args,
    options.timeout
  );

  if (result.schemaVersion !== SUPPORTED_SCAN_MODULES_SCHEMA_VERSION) {
    throw new ScannerSchemaVersionError(
      'scan-modules',
      result.schemaVersion,
      SUPPORTED_SCAN_MODULES_SCHEMA_VERSION
    );
  }
  return result;
}

/**
 * Deep scan of the full JS-exported surface, for TypeScript type generation. Each path is a `.swift`
 * file or a directory, scanned recursively.
 *
 * Each declaration and member reports the Apple OSes whose `#if` conditions and `@available`
 * attributes include it. `#if` is read only where the runtime sees what it holds: around types,
 * `@Event` members, and enum cases. No define option is taken: a condition on a custom flag never holds, so
 * what it guards is not reported.
 */
export async function scanExports(
  paths: string[],
  options: ScanExportsOptions = {}
): Promise<ScanExportsResult> {
  if (paths.length === 0) {
    throw new TypeError('scanExports requires at least one path');
  }
  assertRepresentablePaths('scanExports', paths);

  const result = await runScanner<ScanExportsResult>(
    options.binaryPath ?? getScannerBinaryPath(),
    ['scan-exports', ...paths],
    options.timeout
  );

  if (result.schemaVersion !== SUPPORTED_SCAN_EXPORTS_SCHEMA_VERSION) {
    throw new ScannerSchemaVersionError(
      'scan-exports',
      result.schemaVersion,
      SUPPORTED_SCAN_EXPORTS_SCHEMA_VERSION
    );
  }
  return result;
}
