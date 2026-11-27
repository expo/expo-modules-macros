import SwiftSyntax

/// A `@JS init` collected for direct JSI binding. A class has at most one (JS classes have a single
/// constructor). Instead of a `Constructor { … }` DSL entry, the macro synthesizes a
/// `_constructInstance(...)` hook that decodes the JS arguments and returns a fresh instance; unlike
/// the method/property bindings it produces the native instance rather than recovering one. Like a
/// function, it can take the JavaScript runtime as its last parameter.
internal struct JSConstructor {
  /// The parameters that take JavaScript arguments, without the runtime parameter.
  let parameters: [FunctionParameterSyntax]
  /// The label of the parameter that takes the JavaScript runtime, or `nil` when the initializer has
  /// none.
  private let runtimeLabel: String?
  /// True when the initializer is marked `throws`.
  private let isThrowing: Bool

  init(initDecl: InitializerDeclSyntax) {
    let declaredParameters = initDecl.signature.parameterClause.parameters
    self.parameters = declaredParameters.filter { !isRuntimeParameter($0) }
    self.runtimeLabel = declaredParameters.first(where: isRuntimeParameter)?.firstName.text
    self.isThrowing = initDecl.signature.effectSpecifiers?.throwsClause?.throwsSpecifier != nil
  }

  /// The number of leading parameters that must always be supplied: the total minus the maximal
  /// trailing run of omittable parameters (each having a default value or an optional type).
  private var requiredArgumentCount: Int {
    var required = parameters.count
    for parameter in parameters.reversed() {
      guard isOmittable(parameter) else {
        break
      }
      required -= 1
    }
    return required
  }

  /// The body statements, indented with `indent`: arity guard (exact when every parameter is required,
  /// otherwise a range check), per-argument decode through `JavaScriptDecodable.decode` on a zero-copy
  /// `arguments.unownedValue(at:)` (the arity guard proves each index is in bounds) or a wrapper for a
  /// closure argument, then `return [try] <Type>(label: arg0, ...)`. When a trailing run of parameters
  /// is omittable, the call branches on `arguments.count` so omitted trailing slots are never indexed.
  private func bodyStatements(typeName: String, functionName: String, indent: String) -> String {
    let required = requiredArgumentCount
    let maximum = parameters.count
    var lines: [String] = []

    if required == maximum {
      lines.append(
        """
        guard arguments.count == \(maximum) else {
          throw Exceptions.ArgumentsRangeMismatch((functionName: "\(functionName)", received: arguments.count, required: \(required), maximum: \(maximum)))
        }
        """
      )
    } else {
      lines.append(
        """
        guard arguments.count >= \(required) && arguments.count <= \(maximum) else {
          throw Exceptions.ArgumentsRangeMismatch((functionName: "\(functionName)", received: arguments.count, required: \(required), maximum: \(maximum)))
        }
        """
      )
    }

    for index in 0..<required {
      lines.append(contentsOf: decodeLines(at: index))
    }

    if required == maximum {
      lines.append("return \(callExpression(typeName: typeName, arity: maximum))")
    } else {
      lines.append("switch arguments.count {")
      for arity in required...maximum {
        let label = arity == maximum ? "default:" : "case \(arity):"
        lines.append(label)
        for index in required..<arity {
          lines.append(contentsOf: decodeLines(at: index).map { "  " + $0 })
        }
        lines.append("  return \(callExpression(typeName: typeName, arity: arity))")
      }
      lines.append("}")
    }

    return
      lines
      .flatMap { $0.split(separator: "\n", omittingEmptySubsequences: false) }
      .map { indent + $0 }
      .joined(separator: "\n")
  }

  private func decodeLines(at index: Int) -> [String] {
    return argumentDecodeStatements(
      type: parameters[index].type,
      into: "arg\(index)",
      from: "arguments.unownedValue(at: \(index))"
    )
  }

  private func callExpression(typeName: String, arity: Int) -> String {
    let tryKeyword = isThrowing ? "try " : ""
    return "\(tryKeyword)\(typeName)(\(callArguments(arity: arity)))"
  }

  /// The argument list for the given arity. Slots `0..<arity` pass their decoded `arg<i>`; an omitted
  /// trailing optional without a default passes `nil`; an omitted trailing defaulted slot is dropped so
  /// Swift applies its default.
  private func callArguments(arity: Int) -> String {
    var callArguments: [String] = []
    for (index, parameter) in parameters.enumerated() {
      let label = parameter.firstName.text
      let value: String?
      if index < arity {
        value = "arg\(index)"
      } else if hasDefaultValue(parameter) {
        value = nil
      } else {
        value = "nil"
      }
      guard let value else {
        continue
      }
      callArguments.append(label == "_" ? value : "\(label): \(value)")
    }
    if let runtimeLabel {
      callArguments.append(runtimeLabel == "_" ? "runtime" : "\(runtimeLabel): runtime")
    }
    return callArguments.joined(separator: ", ")
  }

  /// Builds an instance from the JS arguments. It overrides the hook of the superclass, or, in the root
  /// of the chain, implements the requirement of `AnyJavaScriptClass` (`isOverride` is `false`). It
  /// returns the concrete instance, which converts to the `(any AnyJavaScriptClass)?` return type. The
  /// return type can't be `Self?`, since a class that isn't `final` can't return an instance of itself
  /// as `Self`.
  ///
  /// A subclass without a `@JS init` of its own inherits this hook, and would construct an instance of
  /// this class instead of the subclass. Unless the class is `final`, the hook returns `nil` when
  /// called on a subclass, so core reports that the subclass has no JavaScript constructor.
  func buildConstructor(
    typeName: String,
    jsName: String,
    access: String,
    isFinal: Bool,
    isOverride: Bool
  ) -> DeclSyntax {
    let subclassGuard =
      isFinal
      ? ""
      : """
        guard self == \(typeName).self else {
          return nil
        }

      """
    return """
      @JavaScriptActor
      \(raw: access) \(raw: isOverride ? "override " : "")class func _constructInstance(this: borrowing JavaScriptValue, arguments: borrowing JavaScriptValuesBuffer, in runtime: JavaScriptRuntime) throws -> (any AnyJavaScriptClass)? {
      \(raw: subclassGuard)\(raw: bodyStatements(typeName: typeName, functionName: jsName, indent: "  "))
      }
      """
  }

  /// The hook of a root class without a `@JS init`: it returns `nil`, so core reports that the class has
  /// no JavaScript constructor. A root emits it anyway, so that a subclass with a `@JS init` overrides a
  /// class method: a default in a protocol extension couldn't be overridden.
  static func buildAbsentConstructor(access: String) -> DeclSyntax {
    return """
      @JavaScriptActor
      \(raw: access) class func _constructInstance(this: borrowing JavaScriptValue, arguments: borrowing JavaScriptValuesBuffer, in runtime: JavaScriptRuntime) throws -> (any AnyJavaScriptClass)? {
        return nil
      }
      """
  }
}
