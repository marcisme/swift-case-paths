import SwiftDiagnostics
public import SwiftSyntax
import SwiftSyntaxBuilder
public import SwiftSyntaxMacros

#if compiler(>=6.1)
  private let nonisolatedMemberModifier = "nonisolated "
#else
  private let nonisolatedMemberModifier = ""
#endif

#if compiler(>=6.2)
  private let nonisolatedExtensionModifier = "nonisolated "
#else
  private let nonisolatedExtensionModifier = ""
#endif

public struct CasePathableMacro {
  static let moduleName = "CasePaths"
  static let casePathTypeName = "AnyCasePath"
  private static let casePathProtocolNames = [
    "CasePathable",
    "CasePathIterable",
  ]
  static let casePathableExpandingMacroNames = [
    "CaseBindable",
    "Table",
    "Selection",
  ]
  private static let casePathableExpandingMacroModuleNames = [
    "CaseBindable": "SwiftNavigation",
    "Table": "StructuredQueries",
    "Selection": "StructuredQueries",
  ]

  private static func shouldGenerate(
    for node: AttributeSyntax,
    attachedTo declaration: some DeclGroupSyntax,
    in context: some MacroExpansionContext
  ) -> Bool {
    guard !isCasePathableMacro(node.attributeName) else { return true }
    guard isCasePathableExpandingMacro(node.attributeName) else { return false }

    let attributes = coactiveAttributes(with: node, in: declaration.attributes, in: context)
    let hasCasePathableApplied = attributes.contains {
      isCasePathableMacro($0.attributeName)
    }
    guard
      let firstCasePathableExpandableMacroIndex = attributes.firstIndex(where: {
        isCasePathableExpandingMacro($0.attributeName)
      }),
      let nodeIndex = attributes.firstIndex(where: {
        isSameAttribute($0, node, in: context)
      })
    else { return false }

    return !hasCasePathableApplied && firstCasePathableExpandableMacroIndex == nodeIndex
  }

  private static func attributes(in attributes: AttributeListSyntax) -> [AttributeSyntax] {
    attributes.flatMap { element -> [AttributeSyntax] in
      if let attribute = element.as(AttributeSyntax.self) {
        return [attribute]
      }
      guard let ifConfigDecl = element.as(IfConfigDeclSyntax.self) else { return [] }
      return ifConfigDecl.clauses.flatMap { clause -> [AttributeSyntax] in
        guard let attributes = clause.elements?.as(AttributeListSyntax.self) else { return [] }
        return self.attributes(in: attributes)
      }
    }
  }

  /// Flattens `attributes` like ``attributes(in:)``, descending into `#if` clauses — but for
  /// any `#if` that contains `node`, only the branch holding `node` (the active one) is kept.
  /// This keeps attributes from mutually-exclusive `#if`/`#else` branches out of generator
  /// arbitration, so an inactive sibling can't be mistaken for the first expanding macro and
  /// suppress the active delegate.
  private static func coactiveAttributes(
    with node: AttributeSyntax,
    in attributes: AttributeListSyntax,
    in context: some MacroExpansionContext
  ) -> [AttributeSyntax] {
    attributes.flatMap { element -> [AttributeSyntax] in
      if let attribute = element.as(AttributeSyntax.self) {
        return [attribute]
      }
      guard let ifConfigDecl = element.as(IfConfigDeclSyntax.self) else { return [] }
      let clauses = Array(ifConfigDecl.clauses)
      // If `node` lives in one branch, that branch is the active one — keep only it.
      // Otherwise the `#if`'s activeness is unknown, so keep every branch (as before).
      let activeClauses =
        clauses.first { clause in
          guard let attributes = clause.elements?.as(AttributeListSyntax.self) else {
            return false
          }
          return self.attributes(in: attributes).contains {
            isSameAttribute($0, node, in: context)
          }
        }
        .map { [$0] } ?? clauses
      return activeClauses.flatMap { clause -> [AttributeSyntax] in
        guard let attributes = clause.elements?.as(AttributeListSyntax.self) else { return [] }
        return self.coactiveAttributes(with: node, in: attributes, in: context)
      }
    }
  }

  private static func isCasePathableMacro(_ type: TypeSyntax) -> Bool {
    isMacro(type, named: "CasePathable", moduleName: moduleName)
  }

  private static func isCasePathableExpandingMacro(_ type: TypeSyntax) -> Bool {
    casePathableExpandingMacroNames.contains { name in
      guard let moduleName = casePathableExpandingMacroModuleNames[name] else { return false }
      return isMacro(type, named: name, moduleName: moduleName)
    }
  }

  private static func isMacro(
    _ type: TypeSyntax,
    named name: String,
    moduleName: String
  ) -> Bool {
    if let identifier = type.as(IdentifierTypeSyntax.self) {
      return identifier.name.text == name
    }
    guard
      let member = type.as(MemberTypeSyntax.self),
      member.name.text == name,
      let module = member.baseType.as(IdentifierTypeSyntax.self)
    else { return false }
    return module.name.text == moduleName
  }

  private static func isSameAttribute(
    _ lhs: AttributeSyntax,
    _ rhs: AttributeSyntax,
    in context: some MacroExpansionContext
  ) -> Bool {
    if lhs.id == rhs.id { return true }
    guard
      let lhsLocation = context.location(of: lhs),
      let rhsLocation = context.location(of: rhs)
    else { return false }
    return lhsLocation.file.trimmedDescription == rhsLocation.file.trimmedDescription
      && lhsLocation.line.trimmedDescription == rhsLocation.line.trimmedDescription
      && lhsLocation.column.trimmedDescription == rhsLocation.column.trimmedDescription
  }

  private static func macroName(of type: TypeSyntax) -> String? {
    type.as(IdentifierTypeSyntax.self)?.name.text
      ?? type.as(MemberTypeSyntax.self)?.name.text
  }
}

extension CasePathableMacro: ExtensionMacro {
  public static func expansion<D: DeclGroupSyntax, T: TypeSyntaxProtocol, C: MacroExpansionContext>(
    of node: AttributeSyntax,
    attachedTo declaration: D,
    providingExtensionsOf type: T,
    conformingTo protocols: [TypeSyntax],
    in context: C
  ) throws -> [ExtensionDeclSyntax] {
    if protocols.isEmpty {
      return []
    }
    guard declaration.is(EnumDeclSyntax.self)
    else {
      return []
    }
    guard shouldGenerate(for: node, attachedTo: declaration, in: context) else { return [] }
    let conformances =
      protocols
      .filter { type in
        macroName(of: type).map(casePathProtocolNames.contains) ?? false
      }
      .map { "\(nonisolatedExtensionModifier)\($0.trimmedDescription)" }
    guard !conformances.isEmpty else { return [] }
    return [
      DeclSyntax(
        """
        \(declaration.attributes.availability)extension \(type.trimmed): \
        \(raw: conformances.joined(separator: ", ")) {}
        """
      )
      .cast(ExtensionDeclSyntax.self)
    ]
  }
}

extension CasePathableMacro: MemberMacro {
  public static func expansion<
    Declaration: DeclGroupSyntax, Context: MacroExpansionContext
  >(
    of node: AttributeSyntax,
    providingMembersOf declaration: Declaration,
    in context: Context
  ) throws -> [DeclSyntax] {
    try expansion(of: node, providingMembersOf: declaration, conformingTo: [], in: context)
  }

  public static func expansion<
    Declaration: DeclGroupSyntax, Context: MacroExpansionContext
  >(
    of node: AttributeSyntax,
    providingMembersOf declaration: Declaration,
    conformingTo protocols: [TypeSyntax],
    in context: Context
  ) throws -> [DeclSyntax] {
    guard let enumDecl = declaration.as(EnumDeclSyntax.self)
    else {
      // Only a direct `@CasePathable` diagnoses a non-enum. A delegating macro
      // (@Table/@Selection/@CaseBindable) is legitimately applied to non-enums
      // (e.g. `@Table struct`) and must simply contribute no case-path members —
      // mirroring the ExtensionMacro path, which returns [] for non-enums.
      guard isCasePathableMacro(node.attributeName) else { return [] }
      throw DiagnosticsError(
        diagnostics: [
          CasePathableMacroDiagnostic
            .notAnEnum(declaration)
            .diagnose(at: declaration.keyword)
        ]
      )
    }
    guard shouldGenerate(for: node, attachedTo: declaration, in: context) else { return [] }
    let enumName = enumDecl.name.trimmed

    let enumCaseDecls = enumDecl.memberBlock.members
      .flatMap { $0.decl.as(EnumCaseDeclSyntax.self)?.elements ?? [] }

    var seenCaseNames: Set<String> = []
    for enumCaseDecl in enumCaseDecls {
      let name = enumCaseDecl.name.text
      if seenCaseNames.contains(name) {
        throw DiagnosticsError(
          diagnostics: [
            CasePathableMacroDiagnostic.overloadedCaseName(name).diagnose(
              at: Syntax(enumCaseDecl.name))
          ]
        )
      }
      seenCaseNames.insert(name)
    }

    let selfRewriter = SelfRewriter(selfEquivalent: enumName)
    let memberBlock = selfRewriter.rewrite(enumDecl.memberBlock).cast(MemberBlockSyntax.self)
    let rootSubscriptCases = generateCases(from: memberBlock.members, enumName: enumName) {
      "if root.is(\\.\($0.name.text)) { return \\.\($0.name.text) }"
    }
    let elementRewriter = ElementRewriter()
    let casePaths = generateDeclSyntax(
      from: memberBlock.members,
      enumName: enumName,
      elementRewriter: elementRewriter
    )
    let allCases = generateCases(from: memberBlock.members, enumName: enumName) {
      "allCasePaths.append(\\.\($0.name.text))"
    }

    let subscriptReturn = allCases.isEmpty ? #"\.never"# : #"return \.never"#

    var decls: [DeclSyntax] = [
      """
      public \(raw: nonisolatedMemberModifier)struct AllCasePaths: \
      CasePaths.CasePathReflectable, Swift.Sendable, Swift.Sequence {
      public subscript(root: \(enumName)) -> CasePaths.PartialCaseKeyPath<\(enumName)> {
      \(raw: rootSubscriptCases.map { "\($0.description)\n" }.joined())\(raw: subscriptReturn)
      }
      \(raw: casePaths.map(\.description).joined(separator: "\n"))
      public func makeIterator() -> Swift.IndexingIterator<[CasePaths.PartialCaseKeyPath<\(enumName)>]> {
      \(raw: allCases.isEmpty ? "let" : "var") allCasePaths: \
      [CasePaths.PartialCaseKeyPath<\(enumName)>] = []\
      \(raw: allCases.map { "\n\($0.description)" }.joined())
      return allCasePaths.makeIterator()
      }
      }
      """,
      """
      public \(raw: nonisolatedMemberModifier)static var allCasePaths: AllCasePaths { AllCasePaths() }
      """,
    ]

    // Direct-`@CasePathable`-only members go here. Delegating macros
    // (@Table/@Selection/@CaseBindable) declare only `AllCasePaths`/`allCasePaths`/`_$Element`
    // in their `@attached(member, names:)`, so any member emitted below would be rejected as
    // "not covered by macro" when delegated. Keep such members — and the work that feeds
    // them, like `caseNameCases` — inside this guard.
    if isCasePathableMacro(node.attributeName) {
      let caseNameCases = generateCases(from: memberBlock.members, enumName: enumName) {
        #"if keyPath == \.\#($0.name.text) { return "\#($0.name.text)" }"#
      }
      decls.append(
        """
        public \(raw: nonisolatedMemberModifier)static func caseName(
        for keyPath: CasePaths.PartialCaseKeyPath<\(enumName)>
        ) -> Swift.String? {
        \(raw: caseNameCases.map { "\($0.description)\n" }.joined())return nil
        }
        """
      )
    }

    if elementRewriter.didRewriteElement {
      decls.append("public typealias _$Element = Element")
    }

    return decls
  }

  static func generateCases(
    from elements: MemberBlockItemListSyntax,
    enumName: TokenSyntax,
    body: (EnumCaseElementSyntax) -> String
  ) -> [String] {
    elements.flatMap {
      if let decl = $0.decl.as(EnumCaseDeclSyntax.self) {
        return decl.elements.map(body)
      }
      if let ifConfigDecl = $0.decl.as(IfConfigDeclSyntax.self) {
        let ifClauses = ifConfigDecl.clauses.flatMap { decl -> [String] in
          guard let elements = decl.elements?.as(MemberBlockItemListSyntax.self) else {
            return []
          }
          let title = "\(decl.poundKeyword.text) \(decl.condition?.description ?? "")"
          return [title]
            + generateCases(from: elements, enumName: enumName, body: body)
        }
        return ifClauses + ["#endif"]
      }
      return []
    }
  }

  static func generateDeclSyntax(
    from elements: MemberBlockItemListSyntax,
    enumName: TokenSyntax,
    elementRewriter: ElementRewriter
  ) -> [String] {
    elements.flatMap {
      if let decl = $0.decl.as(EnumCaseDeclSyntax.self) {
        return generateDeclSyntax(from: decl, enumName: enumName).map {
          elementRewriter.rewrite($0).description
        }
      }
      if let ifConfigDecl = $0.decl.as(IfConfigDeclSyntax.self) {
        let ifClauses = ifConfigDecl.clauses.flatMap { decl -> [String] in
          guard let elements = decl.elements?.as(MemberBlockItemListSyntax.self) else {
            return []
          }
          let title = "\(decl.poundKeyword.text) \(decl.condition?.description ?? "")"
          return [title]
            + generateDeclSyntax(
              from: elements, enumName: enumName, elementRewriter: elementRewriter
            )
        }
        return ifClauses + ["#endif"]
      }
      return []
    }
  }

  static func generateDeclSyntax(
    from decl: EnumCaseDeclSyntax,
    enumName: TokenSyntax
  ) -> [DeclSyntax] {
    decl.elements.map {
      let caseName = $0.name.trimmed
      let associatedValueType = valueType(for: $0)
      let hasPayload = $0.parameterClause.map { !$0.parameters.isEmpty } ?? false
      let embed: String = hasPayload ? "\(enumName).\(caseName)" : "{ \(enumName).\(caseName) }"
      let bindingNames: String
      let returnName: String
      if hasPayload, let associatedValue = $0.parameterClause {
        let parameterNames = (0..<associatedValue.parameters.count)
          .map { "v\($0)" }
          .joined(separator: ", ")
        bindingNames = "(\(parameterNames))"
        returnName = associatedValue.parameters.count == 1 ? parameterNames : bindingNames
      } else {
        bindingNames = ""
        returnName = "()"
      }
      let leadingTriviaLines = decl.leadingTrivia.description
        .drop(while: \.isNewline)
        .split(separator: "\n", omittingEmptySubsequences: false)
      let indent =
        leadingTriviaLines
        .compactMap { $0.isEmpty ? nil : $0.prefix(while: \.isWhitespace).count }
        .min(by: { (lhs: Int, rhs: Int) -> Bool in lhs < rhs })
        ?? 0
      let leadingTrivia =
        leadingTriviaLines
        .map { String($0.dropFirst(indent)) }
        .joined(separator: "\n")
        .trimmingSuffix(while: { $0.isWhitespace && !$0.isNewline })
      return """
        \(raw: leadingTrivia)public var \(caseName): \
        \(raw: casePathTypeName.qualified)<\(enumName), \(associatedValueType)> {
        \(raw: casePathTypeName.qualified)(embed: \(raw: embed)) {
        guard case\(raw: hasPayload ? " let" : "").\(caseName)\(raw: bindingNames) = $0 else { \
        return nil \
        }
        return \(raw: returnName)
        }
        }
        """
    }
  }
}

enum CasePathableMacroDiagnostic {
  case notAnEnum(any DeclGroupSyntax)
  case overloadedCaseName(String)
}

extension CasePathableMacroDiagnostic: DiagnosticMessage {
  var message: String {
    switch self {
    case .notAnEnum(let decl):
      return """
        '@CasePathable' cannot be applied to\
        \(decl.keywordDescription.map { " \($0)" } ?? "") type\
        \(decl.nameDescription.map { " '\($0)'" } ?? "")
        """
    case .overloadedCaseName(let name):
      return """
        '@CasePathable' cannot be applied to overloaded case name '\(name)'
        """
    }
  }

  var diagnosticID: MessageID {
    switch self {
    case .notAnEnum:
      return MessageID(domain: "MetaEnumDiagnostic", id: "notAnEnum")
    case .overloadedCaseName:
      return MessageID(domain: "MetaEnumDiagnostic", id: "overloadedCaseName")
    }
  }

  var severity: DiagnosticSeverity {
    switch self {
    case .notAnEnum:
      return .error
    case .overloadedCaseName:
      return .error
    }
  }

  func diagnose(at node: Syntax) -> Diagnostic {
    Diagnostic(node: node, message: self)
  }
}

extension AttributeListSyntax {
  var availability: AttributeListSyntax? {
    var elements = [AttributeListSyntax.Element]()
    for element in self {
      if let availability = element.availability {
        elements.append(availability)
      }
    }
    if elements.isEmpty {
      return nil
    }
    return AttributeListSyntax(elements)
  }
}

extension AttributeListSyntax.Element {
  var availability: AttributeListSyntax.Element? {
    switch self {
    case .attribute(let attribute):
      if let availability = attribute.availability {
        return .attribute(availability)
      }
    case .ifConfigDecl(let ifConfig):
      if let availability = ifConfig.availability {
        return .ifConfigDecl(availability)
      }
    @unknown default: return nil
    }
    return nil
  }
}

extension AttributeSyntax {
  var availability: AttributeSyntax? {
    if attributeName.identifier == "available" {
      return self
    } else {
      return nil
    }
  }
}

extension IfConfigClauseSyntax {
  var availability: IfConfigClauseSyntax? {
    if let availability = elements?.availability {
      return with(\.elements, availability)
    } else {
      return nil
    }
  }

  var clonedAsIf: IfConfigClauseSyntax {
    detached.with(\.poundKeyword, .poundIfToken())
  }
}

extension IfConfigClauseSyntax.Elements {
  var availability: IfConfigClauseSyntax.Elements? {
    switch self {
    case .attributes(let attributes):
      if let availability = attributes.availability {
        return .attributes(availability)
      } else {
        return nil
      }
    default:
      return nil
    }
  }
}

extension IfConfigDeclSyntax {
  var availability: IfConfigDeclSyntax? {
    var elements = [IfConfigClauseListSyntax.Element]()
    for clause in clauses {
      if let availability = clause.availability {
        if elements.isEmpty {
          elements.append(availability.clonedAsIf)
        } else {
          elements.append(availability)
        }
      }
    }
    if elements.isEmpty {
      return nil
    } else {
      return with(\.clauses, IfConfigClauseListSyntax(elements))
    }
  }
}

extension DeclGroupSyntax {
  var keyword: Syntax {
    switch self {
    case let syntax as ActorDeclSyntax:
      return Syntax(syntax.actorKeyword)
    case let syntax as ClassDeclSyntax:
      return Syntax(syntax.classKeyword)
    case let syntax as ExtensionDeclSyntax:
      return Syntax(syntax.extensionKeyword)
    case let syntax as ProtocolDeclSyntax:
      return Syntax(syntax.protocolKeyword)
    case let syntax as StructDeclSyntax:
      return Syntax(syntax.structKeyword)
    case let syntax as EnumDeclSyntax:
      return Syntax(syntax.enumKeyword)
    default:
      return Syntax(self)
    }
  }

  var keywordDescription: String? {
    switch self {
    case let syntax as ActorDeclSyntax:
      return syntax.actorKeyword.trimmedDescription
    case let syntax as ClassDeclSyntax:
      return syntax.classKeyword.trimmedDescription
    case let syntax as ExtensionDeclSyntax:
      return syntax.extensionKeyword.trimmedDescription
    case let syntax as ProtocolDeclSyntax:
      return syntax.protocolKeyword.trimmedDescription
    case let syntax as StructDeclSyntax:
      return syntax.structKeyword.trimmedDescription
    case let syntax as EnumDeclSyntax:
      return syntax.enumKeyword.trimmedDescription
    default:
      return nil
    }
  }

  var nameDescription: String? {
    switch self {
    case let syntax as ActorDeclSyntax:
      return syntax.name.trimmedDescription
    case let syntax as ClassDeclSyntax:
      return syntax.name.trimmedDescription
    case let syntax as ExtensionDeclSyntax:
      return syntax.extendedType.trimmedDescription
    case let syntax as ProtocolDeclSyntax:
      return syntax.name.trimmedDescription
    case let syntax as StructDeclSyntax:
      return syntax.name.trimmedDescription
    case let syntax as EnumDeclSyntax:
      return syntax.name.trimmedDescription
    default:
      return nil
    }
  }
}

extension CasePathableMacro {
  public static func valueType(for element: EnumCaseElementSyntax) -> TypeSyntax {
    guard var associatedValue = element.parameterClause, !associatedValue.parameters.isEmpty
    else { return TypeSyntax("Void") }
    if associatedValue.parameters.count == 1,
      let type = associatedValue.parameters.first?.type.trimmed
    {
      return type.is(SomeOrAnyTypeSyntax.self) ? TypeSyntax("(\(type))") : type
    }
    for index in associatedValue.parameters.indices {
      associatedValue.parameters[index].type.trailingTrivia = ""
      associatedValue.parameters[index].defaultValue = nil
      if associatedValue.parameters[index].firstName?.tokenKind == .wildcard {
        associatedValue.parameters[index].colon = nil
        associatedValue.parameters[index].firstName = nil
        associatedValue.parameters[index].secondName = nil
      }
    }
    if let lastIndex = associatedValue.parameters.indices.last {
      associatedValue.parameters[lastIndex] = associatedValue.parameters[lastIndex]
        .with(\.trailingComma, nil)
    }
    return TypeSyntax("(\(associatedValue.parameters.trimmed))")
  }
}

extension SyntaxStringInterpolation {
  mutating func appendInterpolation<Node: SyntaxProtocol>(_ node: Node?) {
    if let node {
      self.appendInterpolation(node)
    }
  }
}

extension TypeSyntax {
  var identifier: String? {
    for token in tokens(viewMode: .all) {
      switch token.tokenKind {
      case .identifier(let identifier):
        return identifier
      default:
        break
      }
    }
    return nil
  }
}

final class SelfRewriter: SyntaxRewriter {
  let selfEquivalent: TokenSyntax

  init(selfEquivalent: TokenSyntax) {
    self.selfEquivalent = selfEquivalent
  }

  override func visit(_ node: IdentifierTypeSyntax) -> TypeSyntax {
    guard node.name.text == "Self"
    else { return super.visit(node) }
    return super.visit(node.with(\.name, self.selfEquivalent))
  }
}

final class ElementRewriter: SyntaxRewriter {
  var didRewriteElement = false

  override func visit(_ node: IdentifierTypeSyntax) -> TypeSyntax {
    guard node.name.text == "Element"
    else { return super.visit(node) }
    didRewriteElement = true
    return super.visit(node.with(\.name, "_$Element"))
  }
}

extension String {
  fileprivate var qualified: String {
    "\(CasePathableMacro.moduleName).\(self)"
  }
}

extension StringProtocol {
  @inline(__always)
  func trimmingSuffix(while condition: (Element) throws -> Bool) rethrows -> Self.SubSequence {
    var view = self[...]

    while let character = view.last, try condition(character) {
      view = view.dropLast()
    }

    return view
  }
}
