#if os(macOS) && canImport(MacroTesting) && swift(>=6.2)
  import CasePathsMacrosSupport
  import CustomDump
  import MacroTesting
  import SwiftSyntax
  import SwiftSyntaxBuilder
  import SwiftSyntaxMacroExpansion
  import SwiftSyntaxMacros
  import Testing

  private enum CaseBindableMacro {}
  private enum SelectionMacro {}
  private enum TableMacro {}

  extension CaseBindableMacro: ExtensionMacro {
    static func expansion(
      of node: AttributeSyntax,
      attachedTo declaration: some DeclGroupSyntax,
      providingExtensionsOf type: some TypeSyntaxProtocol,
      conformingTo protocols: [TypeSyntax],
      in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
      try CasePathableMacro.expansion(
        of: node,
        attachedTo: declaration,
        providingExtensionsOf: type,
        conformingTo: protocols,
        in: context
      )
    }
  }

  extension CaseBindableMacro: MemberMacro {
    static func expansion(
      of node: AttributeSyntax,
      providingMembersOf declaration: some DeclGroupSyntax,
      conformingTo protocols: [TypeSyntax],
      in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
      var decls = try CasePathableMacro.expansion(
        of: node,
        providingMembersOf: declaration,
        conformingTo: protocols,
        in: context
      )
      guard let enumDecl = declaration.as(EnumDeclSyntax.self) else { return decls }
      let elements = enumDecl.memberBlock.members
        .flatMap { $0.decl.as(EnumCaseDeclSyntax.self)?.elements ?? [] }
      let cases = elements.map { element -> String in
        let hasPayload = element.parameterClause.map { !$0.parameters.isEmpty } ?? false
        guard hasPayload else { return "case \(element.name.text)" }
        let type = CasePathableMacro.valueType(for: element)
        return "case \(element.name.text)(SwiftUI.Binding<\(type)>)"
      }
      decls.append(
        """
        public enum BindingEnumeration {
        \(raw: cases.joined(separator: "\n"))
        }
        """
      )
      return decls
    }
  }

  extension TableMacro: ExtensionMacro {
    static func expansion(
      of node: AttributeSyntax,
      attachedTo declaration: some DeclGroupSyntax,
      providingExtensionsOf type: some TypeSyntaxProtocol,
      conformingTo protocols: [TypeSyntax],
      in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
      try CasePathableMacro.expansion(
        of: node,
        attachedTo: declaration,
        providingExtensionsOf: type,
        conformingTo: protocols,
        in: context
      )
    }
  }

  extension TableMacro: MemberMacro {
    static func expansion(
      of node: AttributeSyntax,
      providingMembersOf declaration: some DeclGroupSyntax,
      conformingTo protocols: [TypeSyntax],
      in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
      try CasePathableMacro.expansion(
        of: node,
        providingMembersOf: declaration,
        conformingTo: protocols,
        in: context
      )
    }
  }

  extension SelectionMacro: ExtensionMacro {
    static func expansion(
      of node: AttributeSyntax,
      attachedTo declaration: some DeclGroupSyntax,
      providingExtensionsOf type: some TypeSyntaxProtocol,
      conformingTo protocols: [TypeSyntax],
      in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
      try CasePathableMacro.expansion(
        of: node,
        attachedTo: declaration,
        providingExtensionsOf: type,
        conformingTo: protocols,
        in: context
      )
    }
  }

  extension SelectionMacro: MemberMacro {
    static func expansion(
      of node: AttributeSyntax,
      providingMembersOf declaration: some DeclGroupSyntax,
      conformingTo protocols: [TypeSyntax],
      in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
      try CasePathableMacro.expansion(
        of: node,
        providingMembersOf: declaration,
        conformingTo: protocols,
        in: context
      )
    }
  }

  @Suite(
    .macros([
      CaseBindableMacro.self,
      CasePathableMacro.self,
      SelectionMacro.self,
      TableMacro.self,
    ])
  )
  struct CasePathsMacrosSupportTests {
    @Test func basics() {
      assertMacro {
        """
        @CaseBindable enum Foo {
          case bar
          case baz(Int)
        }
        """
      } expansion: {
        #"""
        enum Foo {
          case bar
          case baz(Int)

          public nonisolated struct AllCasePaths: CasePaths.CasePathReflectable, Swift.Sendable, Swift.Sequence {
            public subscript(root: Foo) -> CasePaths.PartialCaseKeyPath<Foo> {
              if root.is(\.bar) {
                return \.bar
              }
              if root.is(\.baz) {
                return \.baz
              }
              return \.never
            }
            public var bar: CasePaths.AnyCasePath<Foo, Void> {
              CasePaths.AnyCasePath(embed: {
                  Foo.bar
                }) {
                guard case .bar = $0 else {
                  return nil
                }
                return ()
              }
            }
            public var baz: CasePaths.AnyCasePath<Foo, Int> {
              CasePaths.AnyCasePath(embed: Foo.baz) {
                guard case let .baz(v0) = $0 else {
                  return nil
                }
                return v0
              }
            }
            public func makeIterator() -> Swift.IndexingIterator<[CasePaths.PartialCaseKeyPath<Foo>]> {
              var allCasePaths: [CasePaths.PartialCaseKeyPath<Foo>] = []
              allCasePaths.append(\.bar)
              allCasePaths.append(\.baz)
              return allCasePaths.makeIterator()
            }
          }

          public nonisolated static var allCasePaths: AllCasePaths {
            AllCasePaths()
          }

          public enum BindingEnumeration {
            case bar
            case baz(SwiftUI.Binding<Int>)
          }
        }
        """#
      }
    }

    @Test func `with '@CasePathable'`() {
      assertMacro {
        """
        @CaseBindable @CasePathable enum Foo {
          case bar
          case baz(Int)
        }
        """
      } expansion: {
        #"""
        enum Foo {
          case bar
          case baz(Int)

          public enum BindingEnumeration {
            case bar
            case baz(SwiftUI.Binding<Int>)
          }

          public nonisolated struct AllCasePaths: CasePaths.CasePathReflectable, Swift.Sendable, Swift.Sequence {
            public subscript(root: Foo) -> CasePaths.PartialCaseKeyPath<Foo> {
              if root.is(\.bar) {
                return \.bar
              }
              if root.is(\.baz) {
                return \.baz
              }
              return \.never
            }
            public var bar: CasePaths.AnyCasePath<Foo, Void> {
              CasePaths.AnyCasePath(embed: {
                  Foo.bar
                }) {
                guard case .bar = $0 else {
                  return nil
                }
                return ()
              }
            }
            public var baz: CasePaths.AnyCasePath<Foo, Int> {
              CasePaths.AnyCasePath(embed: Foo.baz) {
                guard case let .baz(v0) = $0 else {
                  return nil
                }
                return v0
              }
            }
            public func makeIterator() -> Swift.IndexingIterator<[CasePaths.PartialCaseKeyPath<Foo>]> {
              var allCasePaths: [CasePaths.PartialCaseKeyPath<Foo>] = []
              allCasePaths.append(\.bar)
              allCasePaths.append(\.baz)
              return allCasePaths.makeIterator()
            }
          }

          public nonisolated static var allCasePaths: AllCasePaths {
            AllCasePaths()
          }

          public nonisolated static func caseName(
            for keyPath: CasePaths.PartialCaseKeyPath<Foo>
          ) -> Swift.String? {
            if keyPath == \.bar {
              return "bar"
            }
            if keyPath == \.baz {
              return "baz"
            }
            return nil
          }
        }
        """#
      }
    }

    @Test func `multiple expanding macros generate case paths once`() {
      assertMacro {
        """
        @CaseBindable @Table @Selection enum Foo {
          case bar
          case baz(Int)
        }
        """
      } expansion: {
        #"""
        enum Foo {
          case bar
          case baz(Int)

          public nonisolated struct AllCasePaths: CasePaths.CasePathReflectable, Swift.Sendable, Swift.Sequence {
            public subscript(root: Foo) -> CasePaths.PartialCaseKeyPath<Foo> {
              if root.is(\.bar) {
                return \.bar
              }
              if root.is(\.baz) {
                return \.baz
              }
              return \.never
            }
            public var bar: CasePaths.AnyCasePath<Foo, Void> {
              CasePaths.AnyCasePath(embed: {
                  Foo.bar
                }) {
                guard case .bar = $0 else {
                  return nil
                }
                return ()
              }
            }
            public var baz: CasePaths.AnyCasePath<Foo, Int> {
              CasePaths.AnyCasePath(embed: Foo.baz) {
                guard case let .baz(v0) = $0 else {
                  return nil
                }
                return v0
              }
            }
            public func makeIterator() -> Swift.IndexingIterator<[CasePaths.PartialCaseKeyPath<Foo>]> {
              var allCasePaths: [CasePaths.PartialCaseKeyPath<Foo>] = []
              allCasePaths.append(\.bar)
              allCasePaths.append(\.baz)
              return allCasePaths.makeIterator()
            }
          }

          public nonisolated static var allCasePaths: AllCasePaths {
            AllCasePaths()
          }

          public enum BindingEnumeration {
            case bar
            case baz(SwiftUI.Binding<Int>)
          }
        }
        """#
      }
    }

    @Test func `delegated extension filters unrelated conformances`() throws {
      let declaration = DeclSyntax(
        """
        @CaseBindable enum Foo {
          case bar
        }
        """
      )
      .cast(EnumDeclSyntax.self)
      let attribute = try #require(declaration.attributes.first?.as(AttributeSyntax.self))

      let extensions = try CasePathableMacro.expansion(
        of: attribute,
        attachedTo: declaration,
        providingExtensionsOf: TypeSyntax("Foo"),
        conformingTo: [
          TypeSyntax("CasePaths.CasePathable"),
          TypeSyntax("CasePaths.CasePathIterable"),
          TypeSyntax("CaseBindable"),
        ],
        in: BasicMacroExpansionContext()
      )

      expectNoDifference(
        extensions.map(\.trimmedDescription),
        [
          """
          extension Foo: nonisolated CasePaths.CasePathable, \
          nonisolated CasePaths.CasePathIterable {}
          """
        ]
      )
    }

    @Test func `qualified CasePathable suppresses delegated generation`() throws {
      let declaration = DeclSyntax(
        """
        @CaseBindable @CasePaths.CasePathable enum Foo {
          case bar
        }
        """
      )
      .cast(EnumDeclSyntax.self)
      let attributes = declaration.attributes.compactMap { $0.as(AttributeSyntax.self) }
      let caseBindable = try #require(attributes.first)
      let casePathable = try #require(attributes.last)

      let delegatedMembers = try CasePathableMacro.expansion(
        of: caseBindable,
        providingMembersOf: declaration,
        conformingTo: [],
        in: BasicMacroExpansionContext()
      )
      let explicitMembers = try CasePathableMacro.expansion(
        of: casePathable,
        providingMembersOf: declaration,
        conformingTo: [],
        in: BasicMacroExpansionContext()
      )

      #expect(delegatedMembers.isEmpty)
      #expect(!explicitMembers.isEmpty)
    }

    @Test func `qualified expanding macros generate case paths once`() throws {
      let sourceFile = SourceFileSyntax {
        DeclSyntax(
          """
          @StructuredQueries.Table @StructuredQueries.Selection enum Foo {
            case bar
          }
          """
        )
      }
      let declaration = try #require(sourceFile.statements.first?.item.as(EnumDeclSyntax.self))
      let attributes = declaration.attributes.compactMap { $0.as(AttributeSyntax.self) }
      let table = try #require(attributes.first)
      let selection = try #require(attributes.last)
      let context = BasicMacroExpansionContext(
        sourceFiles: [
          sourceFile: .init(moduleName: "TestModule", fullFilePath: "/tmp/Test.swift")
        ]
      )

      let tableMembers = try CasePathableMacro.expansion(
        of: context.detach(table),
        providingMembersOf: context.detach(declaration),
        conformingTo: [],
        in: context
      )
      let selectionMembers = try CasePathableMacro.expansion(
        of: context.detach(selection),
        providingMembersOf: context.detach(declaration),
        conformingTo: [],
        in: context
      )

      #expect(!tableMembers.isEmpty)
      #expect(selectionMembers.isEmpty)
    }

    @Test func `conditional expanding macro generates case paths`() throws {
      let declaration = DeclSyntax(
        """
        #if DEBUG
        #if FEATURE
        @CaseBindable
        #endif
        #endif
        enum Foo {
          case bar
        }
        """
      )
      .cast(EnumDeclSyntax.self)
      let caseBindable = try #require(attributes(in: declaration.attributes).first)

      let members = try CasePathableMacro.expansion(
        of: caseBindable,
        providingMembersOf: declaration,
        conformingTo: [],
        in: BasicMacroExpansionContext()
      )

      #expect(!members.isEmpty)
    }

    @Test func `conditional CasePathable suppresses delegated generation`() throws {
      let declaration = DeclSyntax(
        """
        #if DEBUG
        @CasePaths.CasePathable
        #endif
        @CaseBindable
        enum Foo {
          case bar
        }
        """
      )
      .cast(EnumDeclSyntax.self)
      let attributes = attributes(in: declaration.attributes)
      let casePathable = try #require(attributes.first)
      let caseBindable = try #require(attributes.last)

      let explicitMembers = try CasePathableMacro.expansion(
        of: casePathable,
        providingMembersOf: declaration,
        conformingTo: [],
        in: BasicMacroExpansionContext()
      )
      let delegatedMembers = try CasePathableMacro.expansion(
        of: caseBindable,
        providingMembersOf: declaration,
        conformingTo: [],
        in: BasicMacroExpansionContext()
      )

      #expect(!explicitMembers.isEmpty)
      #expect(delegatedMembers.isEmpty)
    }

    @Test func `mutually exclusive conditional expanding macros generate case paths`() throws {
      let declaration = DeclSyntax(
        """
        #if FEATURE
        @Selection
        #else
        @CaseBindable
        #endif
        enum Foo {
          case bar
        }
        """
      )
      .cast(EnumDeclSyntax.self)
      // Whichever branch is active, its macro must generate case paths on its own; the
      // inactive sibling in the mutually-exclusive branch must not suppress it.
      for attribute in attributes(in: declaration.attributes) {
        let members = try CasePathableMacro.expansion(
          of: attribute,
          providingMembersOf: declaration,
          conformingTo: [],
          in: BasicMacroExpansionContext()
        )
        #expect(!members.isEmpty)
      }
    }

    @Test func `unrelated qualified macro does not suppress generation`() throws {
      let declaration = DeclSyntax(
        """
        @Other.Table @CaseBindable enum Foo {
          case bar
        }
        """
      )
      .cast(EnumDeclSyntax.self)
      let caseBindable = try #require(
        declaration.attributes.compactMap { $0.as(AttributeSyntax.self) }.last
      )

      let members = try CasePathableMacro.expansion(
        of: caseBindable,
        providingMembersOf: declaration,
        conformingTo: [],
        in: BasicMacroExpansionContext()
      )

      #expect(!members.isEmpty)
    }
  }

  private func attributes(in attributeList: AttributeListSyntax) -> [AttributeSyntax] {
    attributeList.flatMap { element -> [AttributeSyntax] in
      if let attribute = element.as(AttributeSyntax.self) {
        return [attribute]
      }
      guard let ifConfigDecl = element.as(IfConfigDeclSyntax.self) else { return [] }
      return ifConfigDecl.clauses.flatMap { clause -> [AttributeSyntax] in
        guard
          let clauseAttributes = clause.elements?.as(AttributeListSyntax.self)
        else { return [] }
        return attributes(in: clauseAttributes)
      }
    }
  }
#endif
