import SwiftParser
import SwiftSyntax

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension Scanner {
  /// Runs `scan-exports` over `paths`, prints the JSON report to stdout, and returns the exit code
  /// (`0` on success, `1` if encoding fails). The deep counterpart to `runPackages`.
  public static func runExports(paths: [String]) -> Int32 {
    let result = scanExports(paths: paths)

    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(result)
      writeToStandardOutput(String(decoding: data, as: UTF8.self) + "\n")
      return 0
    } catch {
      writeToStandardError("error: failed to encode results: \(error)\n")
      return 1
    }
  }
}

/// Scans `paths` for `@ExpoModule`, `@SharedObject`, `@JSClass`, `@Record`, `@Union`, `@ExpoView`, and
/// `@ViewProps` types plus `Enumerable` enums, and returns their exported surface plus the run's stats.
/// Separate from the public entry so tests can drive it without argv/stdout.
///
/// The pre-filter omits `@Event`: an event only declares a member of a module, shared object or class, so a
/// file containing one already matches on its enclosing type. It does include `Enumerable`, which is a
/// conformance rather than an attribute: an enum is commonly declared in a file of its own, which no
/// macro attribute would match.
///
/// A `@SharedObject` or `@JSClass` class can inherit through a class without a macro, which can be declared in a file that
/// the pre-filter skips. So the names of the classes in a skipped file are kept, and once every other
/// file is walked, the skipped files that declare a superclass the scan hasn't found are parsed too
/// (see `plainClassesDeclaringSuperclasses(of:plainClasses:classFiles:)`). The stats count them as
/// parsed.
func scanExports(paths: [String]) -> ScanExportsResult {
  var modules: [ExportedModule] = []
  var sharedObjects: [ExportedJSClass] = []
  var classes: [ExportedJSClass] = []
  var records: [ExportedRecord] = []
  var enums: [ExportedEnum] = []
  var unions: [ExportedUnion] = []
  var views: [ExportedView] = []
  var viewProps: [ViewPropsDeclaration] = []
  var plainClasses: [PlainClassDeclaration] = []
  // A class name -> the skipped files that may declare it.
  var classFiles: [String: [String]] = [:]

  let fileStats = scanFiles(
    paths: paths,
    macros: [.expoModule, .sharedObject, .jsClass, .record, .union, .expoView, .viewProps],
    conformances: [enumerableConformanceName],
    skipped: { source, file in
      for name in declaredClassNames(in: source) {
        classFiles[name, default: []].append(file)
      }
    },
    process: { source, file in
      let tree = Parser.parse(source: source)
      let visitor = SurfaceVisitor(file: file, tree: tree)
      visitor.walk(tree)
      modules.append(contentsOf: visitor.modules)
      sharedObjects.append(contentsOf: visitor.sharedObjects)
      classes.append(contentsOf: visitor.classes)
      records.append(contentsOf: visitor.records)
      enums.append(contentsOf: visitor.enums)
      unions.append(contentsOf: visitor.unions)
      views.append(contentsOf: visitor.views)
      viewProps.append(contentsOf: visitor.viewProps)
      plainClasses.append(contentsOf: visitor.plainClasses)
    }
  )

  // Refs resolve only once every file has been walked: a type parsed in one file may name a type
  // declared in another, so the full set of declarations has to exist before any lookup is valid. The
  // same holds for a view's `@ViewProps` struct, which is joined before the refs resolve so that the
  // refs in its props resolve from the struct, and for a superclass, so the inherited members are
  // merged last.
  let walked = ExportedSurface(
    modules: modules,
    sharedObjects: sharedObjects,
    classes: classes,
    records: records,
    enums: enums,
    unions: unions,
    views: views
  )
  let clock = ContinuousClock()
  let start = clock.now
  let superclasses = plainClassesDeclaringSuperclasses(
    of: walked,
    plainClasses: plainClasses,
    classFiles: classFiles
  )
  let elapsed = (clock.now - start).components
  let surface = walked.joiningViewProps(viewProps).resolvingRefs()
    .mergingInheritedMembers(through: superclasses.plainClasses)

  return ScanExportsResult(
    schemaVersion: scanExportsSchemaVersion,
    exports: surface,
    stats: ScanStats(
      filesScanned: fileStats.filesScanned,
      filesParsed: fileStats.filesParsed + superclasses.filesParsed,
      durationMs: fileStats.durationMs + Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15
    )
  )
}
