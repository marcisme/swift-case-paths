import CasePathsMacrosSupport
public import SwiftSyntax
public import SwiftSyntaxMacros

public enum CasePathableMacro {}

extension CasePathableMacro: ExtensionMacro {
  public static func expansion<
    Declaration: DeclGroupSyntax, Type: TypeSyntaxProtocol, Context: MacroExpansionContext
  >(
    of node: AttributeSyntax,
    attachedTo declaration: Declaration,
    providingExtensionsOf type: Type,
    conformingTo protocols: [TypeSyntax],
    in context: Context
  ) throws -> [ExtensionDeclSyntax] {
    try CasePathsMacrosSupport.CasePathableMacro.expansion(
      of: node,
      attachedTo: declaration,
      providingExtensionsOf: type,
      conformingTo: protocols,
      in: context
    )
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
    try CasePathsMacrosSupport.CasePathableMacro.expansion(
      of: node,
      providingMembersOf: declaration,
      in: context
    )
  }

  public static func expansion<
    Declaration: DeclGroupSyntax, Context: MacroExpansionContext
  >(
    of node: AttributeSyntax,
    providingMembersOf declaration: Declaration,
    conformingTo protocols: [TypeSyntax],
    in context: Context
  ) throws -> [DeclSyntax] {
    try CasePathsMacrosSupport.CasePathableMacro.expansion(
      of: node,
      providingMembersOf: declaration,
      conformingTo: protocols,
      in: context
    )
  }
}
