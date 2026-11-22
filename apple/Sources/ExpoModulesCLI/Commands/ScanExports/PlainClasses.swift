import SwiftParser
import SwiftSyntax

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// A class without a macro that the surface reports, which a shared object can inherit through. Core
/// builds the JavaScript class of a shared object on the JavaScript class of its nearest superclass
/// with `@SharedObject`, also when a class without the macro is between them. Not encoded.
struct PlainClassDeclaration: Equatable {
  /// The Swift class name, qualified with the types it is nested in (`Media.Base`).
  let name: String

  /// The superclass as written, without generic arguments, or `nil` when there is none or it is
  /// `SharedObject`, `SharedRef` or `AnySharedObject`.
  let declaredSuperclass: String?

  /// The `SharedRef<T>` that the class names as its superclass, or `nil` when it names another one or
  /// none.
  let sharedRef: ExportedSharedRef?

  /// The value of the class's own `nativeRefType` override, or `.none` when it declares none.
  let ownNativeRefType: String??

  /// The platforms that build the class.
  let platforms: [ExportedPlatform]
}

/// The names that follow the `class` keyword in `source`, without parsing it. The pre-filter skips the
/// parse of a file without a macro, but a shared object can inherit through a class declared in such a
/// file, so `scanExports` keeps these names to find the file. An over-approximation, like the
/// pre-filter: the keyword also matches in a comment or a string, and in `class func` or `class var`,
/// which adds names that no lookup asks for.
func declaredClassNames(in source: String) -> Set<String> {
  var source = source
  return source.withUTF8 { bytes in
    let keyword = Array("class".utf8)
    var names: Set<String> = []
    var index = 0
    while index < bytes.count {
      guard startsWord(keyword, in: bytes, at: index) else {
        index += 1
        continue
      }
      var cursor = index + keyword.count
      guard cursor < bytes.count, isWhitespace(bytes[cursor]) else {
        index = cursor
        continue
      }
      while cursor < bytes.count, isWhitespace(bytes[cursor]) {
        cursor += 1
      }
      // A name in backticks, such as `` `Type` ``.
      if cursor < bytes.count, bytes[cursor] == UInt8(ascii: "`") {
        cursor += 1
      }
      let start = cursor
      while cursor < bytes.count, isIdentifierByte(bytes[cursor]) {
        cursor += 1
      }
      if cursor > start {
        names.insert(String(decoding: UnsafeBufferPointer(rebasing: bytes[start..<cursor]), as: UTF8.self))
      }
      index = cursor
    }
    return names
  }
}

/// Parses the files that the pre-filter skipped and that may declare a superclass of a shared object
/// that the scan hasn't found, and returns the classes without a macro in them, with the number of files
/// it parsed. `classFiles` maps a class name to the skipped files that may declare it (see
/// `declaredClassNames(in:)`). A class found this way can name another superclass that the scan hasn't
/// found, so it repeats until no new file can declare one. A skipped file has no macro, so it adds only
/// classes without a macro.
func plainClassesDeclaringSuperclasses(
  of surface: ExportedSurface,
  plainClasses: [PlainClassDeclaration],
  classFiles: [String: [String]]
) -> (plainClasses: [PlainClassDeclaration], filesParsed: Int) {
  var plainClasses = plainClasses
  var visitedFiles: Set<String> = []
  var filesParsed = 0
  while true {
    let resolver = SuperclassResolver(surface: surface, plainClasses: plainClasses)
    let files = Set(resolver.unresolvedSuperclassNames().flatMap { classFiles[$0] ?? [] })
      .subtracting(visitedFiles)
    guard !files.isEmpty else {
      return (plainClasses, filesParsed)
    }
    for file in files.sorted() {
      visitedFiles.insert(file)
      guard let source = try? String(contentsOfFile: file, encoding: .utf8) else {
        continue
      }
      filesParsed += 1
      let tree = Parser.parse(source: source)
      let visitor = SurfaceVisitor(file: file, tree: tree)
      visitor.walk(tree)
      plainClasses.append(contentsOf: visitor.plainClasses)
    }
  }
}

/// True if `word` starts at `index` and the byte before it can't be part of an identifier.
private func startsWord(_ word: [UInt8], in bytes: UnsafeBufferPointer<UInt8>, at index: Int) -> Bool {
  guard index + word.count <= bytes.count, index == 0 || !isIdentifierByte(bytes[index - 1]) else {
    return false
  }
  for offset in word.indices where bytes[index + offset] != word[offset] {
    return false
  }
  return true
}

private func isWhitespace(_ byte: UInt8) -> Bool {
  return byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\t") || byte == UInt8(ascii: "\n")
    || byte == UInt8(ascii: "\r")
}

/// An ASCII letter, digit or underscore, or a byte of a non-ASCII character, which Swift identifiers
/// can contain.
private func isIdentifierByte(_ byte: UInt8) -> Bool {
  switch byte {
  case UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "A")...UInt8(ascii: "Z"),
    UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "_"):
    return true
  default:
    return byte >= 0x80
  }
}
