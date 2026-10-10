#!/usr/bin/env node

const childProcess = require('node:child_process');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { promisify } = require('node:util');

const execFile = promisify(childProcess.execFile);

/** The Swift package, where `swift build` runs and the macOS binary is written. */
const packageDir = path.join(__dirname, '..', 'apple');

/** The npm packages that ship the Windows binaries, one per architecture. */
const platformsDir = path.join(__dirname, '..', 'platforms');

/**
 * Runs a command and resolves when it exits successfully.
 */
function spawnAsync(command, args, options = {}) {
  return new Promise((resolve, reject) => {
    const child = childProcess.spawn(command, args, { stdio: 'inherit', ...options });
    child.once('error', reject);
    child.once('close', (code, signal) => {
      if (code === 0) {
        resolve();
      } else {
        reject(new Error(`\`${command} ${args.join(' ')}\` exited with ${signal ?? `code ${code}`}`));
      }
    });
  });
}

/**
 * The `swift build` arguments for the release tool. The build uses the native build system because
 * Swift Build, the default since Swift 6.4, builds nothing for this package: its only executable is
 * the macro tool, which Swift Build only builds as a dependency of a target that uses the macros.
 */
const releaseBuildArgs = ['build', '-c', 'release', '--build-system', 'native'];

/**
 * The extra `swift build` arguments on Windows. `-static-stdlib` links the Swift runtime into the
 * executable, so it runs without a Swift toolchain on PATH and doesn't depend on the version of one
 * (Swift has no stable ABI on Windows). SwiftPM's `--static-swift-stdlib` has no effect on Windows,
 * so the flag goes to the compiler directly. The static Swift concurrency runtime needs libdispatch
 * and the blocks runtime, which nothing else links when the tool doesn't use full Foundation, so they
 * are named for the linker. `-gnone` leaves out debug info, which would otherwise be embedded in the
 * executable.
 */
const windowsBuildArgs = [
  '-Xswiftc', '-static-stdlib',
  '-Xlinker', 'dispatch.lib',
  '-Xlinker', 'BlocksRuntime.lib',
  '-Xswiftc', '-gnone',
];

/**
 * Runs `swift` with the given arguments, under `arch -${arch}` when `arch` is given and isn't the
 * host architecture, and resolves with its stdout.
 */
async function swiftOutput(args, arch) {
  const { stdout } = arch && arch !== os.machine()
    ? await execFile('arch', [`-${arch}`, 'swift', ...args], { cwd: packageDir })
    : await execFile('swift', args, { cwd: packageDir });
  return stdout;
}

/**
 * Returns the path of the release tool that `swift build` produced, asking SwiftPM for the bin
 * directory rather than assuming its layout. `arch` selects the macOS architecture to ask for.
 */
async function builtToolPath(extraArgs, arch) {
  const stdout = await swiftOutput([...releaseBuildArgs, ...extraArgs, '--show-bin-path'], arch);
  const binDir = stdout.trim();
  const toolPath = path.join(binDir, process.platform === 'win32' ? 'ExpoModulesMacros-tool.exe' : 'ExpoModulesMacros-tool');
  try {
    await fs.access(toolPath);
  } catch {
    throw new Error(`Could not find the built ExpoModulesMacros-tool at ${toolPath}`);
  }
  return toolPath;
}

/**
 * Builds the macro plugin for the given architecture and returns the path to the built binary.
 * SwiftPM always builds macro tools for the host architecture, so the x86_64 slice
 * is built by running the whole toolchain under Rosetta with `arch -${arch}`.
 */
async function buildForArch(arch) {
  if (arch === os.machine()) {
    await spawnAsync('swift', releaseBuildArgs, { cwd: packageDir });
  } else {
    await spawnAsync('arch', [`-${arch}`, 'swift', ...releaseBuildArgs], { cwd: packageDir });
  }
  return builtToolPath([], arch);
}

/**
 * Checks whether the Swift toolchain actually runs for the given architecture by
 * verifying the host target triple it reports, e.g. `Target: x86_64-apple-macosx26.0`
 * under Rosetta. Exit status alone is not enough: if `arch` ever fell back to the
 * native architecture, the probe would pass but the build would produce a wrong slice.
 */
async function canRunSwiftForArch(arch) {
  try {
    const { stdout } = await execFile('arch', [`-${arch}`, 'swift', '--version']);
    return stdout.includes(`${arch}-apple`);
  } catch {
    return false;
  }
}

/**
 * Checks whether the toolchain can build for the given architecture.
 * Building x86_64 on Apple Silicon requires Rosetta, so when it is missing,
 * try to install it before giving up.
 */
async function canBuildForArch(arch) {
  if (arch === os.machine()) {
    return true;
  }
  if (await canRunSwiftForArch(arch)) {
    return true;
  }
  if (arch === 'x86_64' && os.machine() === 'arm64') {
    try {
      console.log('Installing Rosetta to build the x86_64 slice...');
      await spawnAsync('sudo', ['softwareupdate', '--install-rosetta', '--agree-to-license']);
      return await canRunSwiftForArch(arch);
    } catch {
      // No sudo access or the install failed - fall through to the unsupported arch warning.
    }
  }
  return false;
}

/**
 * Asserts that the built binary contains a slice for each of the given architectures.
 */
async function verifyArchs(binaryPath, archs) {
  const { stdout } = await execFile('lipo', ['-archs', binaryPath]);
  const builtArchs = stdout.trim().split(/\s+/);
  for (const arch of archs) {
    if (!builtArchs.includes(arch)) {
      throw new Error(`The built binary at ${binaryPath} is missing the ${arch} slice`);
    }
  }
}

/**
 * The PE machine types of the Windows architectures the tool is built for, keyed by `process.arch`.
 */
const windowsMachineTypes = { x64: 0x8664, arm64: 0xaa64 };

/**
 * Asserts that the Windows executable at `binaryPath` is built for `arch`, by reading the machine
 * type from its PE header: the 32-bit offset of the `PE\0\0` signature is at 0x3C, and the 16-bit
 * machine type follows the signature.
 */
async function verifyWindowsArch(binaryPath, arch) {
  const contents = await fs.readFile(binaryPath);
  const peOffset = contents.readUInt32LE(0x3c);
  if (contents.toString('latin1', peOffset, peOffset + 4) !== 'PE\0\0') {
    throw new Error(`The built binary at ${binaryPath} is not a PE executable`);
  }
  const machine = contents.readUInt16LE(peOffset + 4);
  if (machine !== windowsMachineTypes[arch]) {
    throw new Error(
      `The built binary at ${binaryPath} has machine type 0x${machine.toString(16)}, not the one for ${arch}`
    );
  }
}

/**
 * Builds the Windows tool for the host architecture as `ExpoModulesMacros.exe` in the package for
 * that architecture, `platforms/win32-<arch>`, named by `process.arch` (`x64` or `arm64`). Unlike on
 * macOS there are no universal binaries, and SwiftPM builds macro tools only for the host, so each
 * architecture is built on a machine of its own.
 */
async function mainWindows() {
  const arch = process.arch;
  if (!(arch in windowsMachineTypes)) {
    throw new Error(`Building on Windows ${arch} is not supported`);
  }
  const outputPath = path.join(platformsDir, `win32-${arch}`, 'ExpoModulesMacros.exe');

  await spawnAsync('swift', [...releaseBuildArgs, ...windowsBuildArgs], { cwd: packageDir });
  const toolPath = await builtToolPath(windowsBuildArgs);

  await fs.rm(outputPath, { force: true });
  await fs.copyFile(toolPath, outputPath);
  // The Swift toolchain for Windows ships `llvm-strip` next to `swift`. Stripping drops the symbols
  // and the debug sections the linker kept, about half of the executable's size.
  await spawnAsync('llvm-strip', [outputPath]);
  await verifyWindowsArch(outputPath, arch);
  console.log(`Built ${outputPath} for ${arch}`);
}

async function mainMacOS() {
  const outputPath = path.join(packageDir, 'ExpoModulesMacros');

  const archs = [];
  for (const arch of ['arm64', 'x86_64']) {
    if (await canBuildForArch(arch)) {
      archs.push(arch);
    } else {
      console.warn(`The Swift toolchain cannot run for ${arch} - the built binary will not support ${arch} Macs.`);
    }
  }
  if (archs.length === 0) {
    throw new Error('The Swift toolchain is not available for any supported architecture');
  }

  // Builds run sequentially as SwiftPM locks the shared .build directory.
  const binPaths = [];
  for (const arch of archs) {
    binPaths.push(await buildForArch(arch));
  }

  await fs.rm(outputPath, { force: true });
  if (binPaths.length > 1) {
    await spawnAsync('lipo', ['-create', ...binPaths, '-output', outputPath]);
  } else {
    await fs.copyFile(binPaths[0], outputPath);
  }

  await spawnAsync('strip', [outputPath]);
  await verifyArchs(outputPath, archs);
  await spawnAsync('lipo', ['-info', outputPath]);
}

async function main() {
  if (process.platform === 'win32') {
    await mainWindows();
  } else {
    await mainMacOS();
  }
}

main().catch((error) => {
  console.error('Build failed:', error.message);
  process.exit(1);
});
