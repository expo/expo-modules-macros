import ExpoModulesCLI
import SwiftBasicFormat
import SwiftDiagnostics
import SwiftParser
import SwiftParserDiagnostics
import SwiftSyntax
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros

/// A macro that the plugin provides, with the attribute name and the extension conformances of its
/// declaration in `expo-modules-core`.
struct ProvidedMacro {
  let name: String
  let type: Macro.Type
  var conformances: [TypeSyntax] = []

  /// Every macro of the plugin. The compiler gets the types from `providingMacros`, and `expand`
  /// matches the attributes by name and passes the same conformances as the compiler, so both read
  /// this list.
  static var all: [ProvidedMacro] {
    [
      ProvidedMacro(name: "OptimizedFunction", type: OptimizedFunctionAttachedMacro.self),
      ProvidedMacro(name: "JS", type: JSMacro.self),
      ProvidedMacro(name: "Event", type: EventMacro.self),
      ProvidedMacro(name: "ExpoModule", type: ExpoModuleMacro.self, conformances: ["AnyModule"]),
      ProvidedMacro(name: "SharedObject", type: SharedObjectMacro.self),
      ProvidedMacro(name: "Record", type: RecordMacro.self, conformances: ["Record"]),
      ProvidedMacro(
        name: "Union",
        type: UnionMacro.self,
        conformances: ["JavaScriptDecodable", "JavaScriptEncodable"]
      ),
      ProvidedMacro(name: "ViewProps", type: ViewPropsMacro.self, conformances: ["AnyViewProps"]),
      ProvidedMacro(name: "ExpoView", type: ExpoViewMacro.self),
    ]
  }
}

/// Expands the macros of the plugin in one source file in process, with the same swift-syntax
/// machinery as `assertMacroExpansion`. The macros only read the syntax tree, so the generated code
/// is what the compiler gets, except for the names from `makeUniqueName`. The compiler also skips the
/// extension conformances that a type already has; the macros check the inheritance clause for that
/// too, so the result differs only when a conformance is inherited from somewhere else.
///
/// Without `symbols`, it returns one expansion of the whole file. Otherwise it returns one expansion
/// for each symbol declared in the file, and only the diagnostics inside those declarations:
///
/// - A type (`MyModule`, `MyModule.Options`): the expanded type and the extensions that its macros
///   add.
/// - A member (`MyModule.greet`, `MyModule.init`): the expanded type that declares it, with only the
///   declarations of that name (all overloads). The member macros of the type then generate only the
///   code for that member. A macro that reads other members (for example to find a name collision)
///   can generate a little differently than for the whole type.
///
/// A symbol that the file doesn't declare is left out of the expansions.
public func expandMacros(source: String, file: String, symbols: [String]) -> ExpandedFile {
  let tree = Parser.parse(source: source)
  let converter = SourceLocationConverter(fileName: file, tree: tree)
  let (expanded, context) = expand(tree, file: file)

  var diagnostics = ParseDiagnosticsGenerator.diagnostics(for: tree).map { diagnostic in
    expansionDiagnostic(diagnostic) { position, _ in converter.location(for: position) }
  }
  diagnostics += context.diagnostics.map { diagnostic in
    expansionDiagnostic(diagnostic) { position, node in
      context.location(for: position, anchoredAt: node, fileName: file)
    }
  }
  diagnostics.sort { ($0.line, $0.column) < ($1.line, $1.column) }

  guard !symbols.isEmpty else {
    return ExpandedFile(
      file: file,
      expansions: [Expansion(symbol: nil, source: expanded.description)],
      diagnostics: diagnostics
    )
  }

  let declarations = SymbolIndex(tree).declarations
  var expansions: [Expansion] = []
  var lineRanges: [ClosedRange<Int>] = []
  for symbol in symbols {
    let types = declarations.filter { $0.path == symbol && $0.kind == .type }
    let members = declarations.filter { $0.path == symbol && $0.kind == .member }

    if !types.isEmpty {
      let source = render(typePath: symbol, kinds: [.type], in: expanded, original: tree)
      expansions.append(Expansion(symbol: symbol, source: source))
      lineRanges += types.map { lineRange(of: $0.node, converter: converter) }
    } else if !members.isEmpty {
      let pruned = MemberPruner(
        parents: Set(members.compactMap(\.parent?.id)),
        kept: Set(members.map(\.node.id))
      )
      .rewrite(tree)
      guard let prunedTree = pruned.as(SourceFileSyntax.self) else {
        continue
      }
      let parentPath = String(symbol[..<(symbol.lastIndex(of: ".") ?? symbol.startIndex)])
      let parentKinds = Set(declarations.filter { members.map(\.parent?.id).contains($0.node.id) }.map(\.kind))
      let (prunedExpansion, _) = expand(prunedTree, file: file)
      let source = render(typePath: parentPath, kinds: parentKinds, in: prunedExpansion, original: prunedTree)
      expansions.append(Expansion(symbol: symbol, source: source))
      lineRanges += members.map { lineRange(of: $0.node, converter: converter) }
    }
  }

  return ExpandedFile(
    file: file,
    expansions: expansions,
    diagnostics: diagnostics.filter { diagnostic in
      lineRanges.contains { $0.contains(diagnostic.line) }
    }
  )
}

/// Expands every macro of the plugin in `tree`.
private func expand(
  _ tree: SourceFileSyntax,
  file: String
) -> (expanded: Syntax, context: BasicMacroExpansionContext) {
  let specs = Dictionary(
    uniqueKeysWithValues: ProvidedMacro.all.map {
      ($0.name, MacroSpec(type: $0.type, conformances: $0.conformances))
    }
  )
  let context = BasicMacroExpansionContext(
    sourceFiles: [tree: .init(moduleName: "ExpandedModule", fullFilePath: file)]
  )
  let expanded = tree.expand(
    macroSpecs: specs,
    contextGenerator: { node in
      BasicMacroExpansionContext(sharingWith: context, lexicalContext: node.allMacroLexicalContexts())
    },
    // The generated code follows the indentation of the file.
    indentationWidth: BasicFormat.inferIndentation(of: tree) ?? .spaces(2)
  )
  return (expanded, context)
}

/// The expanded declarations of the given kinds at `typePath`, each without the indentation of its
/// nesting, followed by the extensions that the extension macros add for the type.
private func render(
  typePath: String,
  kinds: Set<SymbolDeclaration.Kind>,
  in expanded: Syntax,
  original: SourceFileSyntax
) -> String {
  let declarations = SymbolIndex(expanded).declarations.filter {
    $0.path == typePath && kinds.contains($0.kind)
  }
  // The macro system adds the extensions after the expanded statements of the file, with the type
  // name as the macro got it (qualified for a nested type). So they are the last statements, after
  // the extensions that already end the file.
  let typeName = String(typePath.split(separator: ".").last ?? "")
  let statements = expanded.as(SourceFileSyntax.self)?.statements ?? []
  let addedCount =
    trailingExtensions(of: statements).count - trailingExtensions(of: original.statements).count
  let addedExtensions = trailingExtensions(of: statements).suffix(max(addedCount, 0)).filter {
    let extendedType = $0.extendedType.trimmedDescription
    return extendedType == typePath || extendedType == typeName
  }
  let nodes = declarations.map(\.node) + addedExtensions.map(Syntax.init)
  return nodes.map(withoutNestingIndentation).joined(separator: "\n\n") + "\n"
}

/// The extensions at the end of `statements`, up to the last statement that isn't one.
private func trailingExtensions(of statements: CodeBlockItemListSyntax) -> [ExtensionDeclSyntax] {
  var extensions: [ExtensionDeclSyntax] = []
  for item in statements.reversed() {
    guard let extensionDecl = item.item.as(ExtensionDeclSyntax.self) else {
      break
    }
    extensions.insert(extensionDecl, at: 0)
  }
  return extensions
}

/// The source of `node` without its leading trivia, and with the indentation of its first line
/// removed from all the lines.
private func withoutNestingIndentation(_ node: Syntax) -> String {
  var indentation = ""
  for piece in node.leadingTrivia.pieces {
    switch piece {
    case .newlines, .carriageReturns, .carriageReturnLineFeeds:
      indentation = ""
    case .spaces(let count):
      indentation += String(repeating: " ", count: count)
    case .tabs(let count):
      indentation += String(repeating: "\t", count: count)
    default:
      break
    }
  }
  let lines = node.trimmedDescription.split(separator: "\n", omittingEmptySubsequences: false)
  return lines.enumerated().map { index, line in
    index > 0 && line.hasPrefix(indentation) ? String(line.dropFirst(indentation.count)) : String(line)
  }
  .joined(separator: "\n")
}

/// The lines of `node` in the original file, from its attributes to its closing brace.
private func lineRange(of node: Syntax, converter: SourceLocationConverter) -> ClosedRange<Int> {
  let start = converter.location(for: node.positionAfterSkippingLeadingTrivia).line
  let end = converter.location(for: node.endPositionBeforeTrailingTrivia).line
  return start...end
}

private func expansionDiagnostic(
  _ diagnostic: Diagnostic,
  location: (AbsolutePosition, Syntax) -> SourceLocation
) -> ExpansionDiagnostic {
  let start = location(diagnostic.position, diagnostic.node)
  return ExpansionDiagnostic(
    severity: severity(diagnostic.diagMessage.severity),
    message: diagnostic.message,
    line: start.line,
    column: start.column,
    notes: diagnostic.notes.map { note in
      let noteStart = location(note.position, note.node)
      return ExpansionNote(message: note.message, line: noteStart.line, column: noteStart.column)
    },
    fixIts: diagnostic.fixIts.map(\.message.message)
  )
}

private func severity(_ severity: DiagnosticSeverity) -> ExpansionDiagnostic.Severity {
  switch severity {
  case .error: .error
  case .warning: .warning
  case .note: .note
  case .remark: .remark
  }
}

// MARK: - Symbols

/// A declaration that `--symbol` can name.
private struct SymbolDeclaration {
  enum Kind {
    case type
    case `extension`
    case member
  }

  /// The names from the outermost type to the declaration, joined with dots: `MyModule.greet`. An
  /// extension has the path of the type it extends.
  let path: String
  let kind: Kind
  let node: Syntax

  /// For a member, the type or extension that declares it.
  let parent: Syntax?
}

/// Collects the types, extensions and members in a tree, also those inside `#if` blocks. Function
/// bodies are skipped, so a local type isn't a symbol.
private final class SymbolIndex: SyntaxVisitor {
  private(set) var declarations: [SymbolDeclaration] = []
  private var scopes: [(path: String, node: Syntax)] = []

  init(_ tree: some SyntaxProtocol) {
    super.init(viewMode: .sourceAccurate)
    walk(tree)
  }

  override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
    enterType(node, name: node.name)
  }

  override func visitPost(_ node: ClassDeclSyntax) {
    scopes.removeLast()
  }

  override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
    enterType(node, name: node.name)
  }

  override func visitPost(_ node: StructDeclSyntax) {
    scopes.removeLast()
  }

  override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
    enterType(node, name: node.name)
  }

  override func visitPost(_ node: EnumDeclSyntax) {
    scopes.removeLast()
  }

  override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
    enterType(node, name: node.name)
  }

  override func visitPost(_ node: ActorDeclSyntax) {
    scopes.removeLast()
  }

  override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
    enterType(node, name: node.name)
  }

  override func visitPost(_ node: ProtocolDeclSyntax) {
    scopes.removeLast()
  }

  override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
    let path = qualified(node.extendedType.trimmedDescription)
    declarations.append(SymbolDeclaration(path: path, kind: .extension, node: Syntax(node), parent: nil))
    scopes.append((path, Syntax(node)))
    return .visitChildren
  }

  override func visitPost(_ node: ExtensionDeclSyntax) {
    scopes.removeLast()
  }

  override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
    addMember(node, names: [node.name.text])
  }

  override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
    addMember(
      node,
      names: node.bindings.compactMap { $0.pattern.as(IdentifierPatternSyntax.self)?.identifier.text }
    )
  }

  override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
    addMember(node, names: ["init"])
  }

  override func visit(_ node: SubscriptDeclSyntax) -> SyntaxVisitorContinueKind {
    addMember(node, names: ["subscript"])
  }

  override func visit(_ node: EnumCaseDeclSyntax) -> SyntaxVisitorContinueKind {
    addMember(node, names: node.elements.map(\.name.text))
  }

  private func enterType(_ node: some DeclSyntaxProtocol, name: TokenSyntax) -> SyntaxVisitorContinueKind {
    let path = qualified(name.text)
    declarations.append(SymbolDeclaration(path: path, kind: .type, node: Syntax(node), parent: nil))
    scopes.append((path, Syntax(node)))
    return .visitChildren
  }

  /// Records a member of the innermost type. Doesn't visit the children: a declaration in a body or
  /// an accessor isn't a member.
  private func addMember(_ node: some DeclSyntaxProtocol, names: [String]) -> SyntaxVisitorContinueKind {
    if let scope = scopes.last {
      for name in names {
        declarations.append(
          SymbolDeclaration(path: "\(scope.path).\(name)", kind: .member, node: Syntax(node), parent: scope.node)
        )
      }
    }
    return .skipChildren
  }

  /// `name` inside the innermost type. Backticks are dropped, so `` `default` `` is `default`.
  private func qualified(_ name: String) -> String {
    let name = name.filter { $0 != "`" }
    return scopes.last.map { "\($0.path).\(name)" } ?? name
  }
}

/// Removes from the member blocks of `parents` every member that isn't in `kept`. An `#if` block
/// stays with the kept members inside it.
private final class MemberPruner: SyntaxRewriter {
  private let parents: Set<SyntaxIdentifier>
  private let kept: Set<SyntaxIdentifier>

  init(parents: Set<SyntaxIdentifier>, kept: Set<SyntaxIdentifier>) {
    self.parents = parents
    self.kept = kept
    super.init(viewMode: .sourceAccurate)
  }

  override func visit(_ node: MemberBlockSyntax) -> MemberBlockSyntax {
    guard let parent = node.parent, parents.contains(parent.id) else {
      return super.visit(node)
    }
    return node.with(\.members, prune(node.members))
  }

  private func prune(_ members: MemberBlockItemListSyntax) -> MemberBlockItemListSyntax {
    MemberBlockItemListSyntax(
      members.compactMap { item -> MemberBlockItemSyntax? in
        if kept.contains(item.decl.id) {
          return item
        }
        guard let ifConfig = item.decl.as(IfConfigDeclSyntax.self) else {
          return nil
        }
        let clauses = ifConfig.clauses.map { clause -> IfConfigClauseSyntax in
          guard case .decls(let decls) = clause.elements else {
            return clause
          }
          return clause.with(\.elements, .decls(prune(decls)))
        }
        let keepsMember = clauses.contains { clause in
          guard case .decls(let decls) = clause.elements else {
            return false
          }
          return !decls.isEmpty
        }
        return keepsMember
          ? item.with(\.decl, DeclSyntax(ifConfig.with(\.clauses, IfConfigClauseListSyntax(clauses)))) : nil
      }
    )
  }
}
