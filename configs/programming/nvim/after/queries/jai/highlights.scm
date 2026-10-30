[
  (import)
  (load)
] @keyword.import

[
  "xx"

  "ifx"

  "then"
  "null"
  "enum"
  "true"
  "cast"

  "using"
  "defer"
  "false"
  "union"

  "struct"
  "inline"
  "remove"

  "type_of"

  "operator"

  "no_inline"
  "interface"

  "enum_flags"

  "push_context"

] @keyword

[
  "return"
] @keyword.return

[
  "if"
  "else"
  "case"
] @keyword.conditional

((if_expression
  [
    "then"
    "ifx"
    "else"
  ] @keyword.conditional.ternary)
  (#set! "priority" 105))

[
  "for"
  "while"
  "break"
  "continue"
] @keyword.repeat

name: (identifier) @variable
argument: (identifier) @variable
named_argument: (identifier) @variable
(member_expression (identifier) @variable)
(parenthesized_expression (identifier) @variable)

((identifier) @variable.builtin
  (#any-of? @variable.builtin "context"))

(import (identifier) @module)

(parameter (identifier) @variable.parameter ":" "="? (identifier)? @constant)

(procedure_declaration (identifier) @function (block))

(call_expression function: (identifier) @function.call)

type: (types) @type
type: (identifier) @type
((types) @type)

modifier: (identifier) @keyword
keyword: (identifier) @keyword

((types (identifier) @type.builtin)
  (#any-of? @type.builtin
    "bool" "int" "string"
    "s8" "s16" "s32" "s64"
    "u8" "u16" "u32" "u64"
    "Type" "Any"))

(struct_declaration (identifier) @type ":" ":")

(enum_declaration (identifier) @type ":" ":")

(member_expression "." (identifier) @variable.member)

(assignment_statement (identifier) @variable.member "="?)
(update_statement (identifier) @variable.member)

((identifier) @constant
  (#lua-match? @constant "^_*[A-Z][A-Z0-9_]*$")
  (#not-has-parent? @constant type parameter))

(member_expression . "." (identifier) @constant)

(enum_field (identifier) @constant)

(integer) @number
(float) @number

(string) @string

(string_contents (escape_sequence) @string.escape)

(boolean) @boolean

[
  (uninitialized)
  (null)
] @constant.builtin

[
  ":"
  "="
  "+"
  "-"
  "*"
  "/"
  "%"
  ">"
  ">="
  "<"
  "<="
  "=="
  "!="
  "|"
  "~"
  "&"
  "&~"
  "<<"
  ">>"
  "<<<"
  ">>>"
  "||"
  "&&"
  "!"
  ".."
  "+="
  "-="
  "*="
  "/="
  "%="
  "&="
  "|="
  "^="
  "<<="
  ">>="
  "<<<="
  ">>>="
  "||="
  "&&="
] @operator

[ "{" "}" ] @punctuation.bracket

[ "(" ")" ] @punctuation.bracket

[ "[" "]" ] @punctuation.bracket

[
  "`"
  "->"
  "."
  ","
  ":"
  ";"
] @punctuation.delimiter

[
  (block_comment)
  (comment)
] @spell

[
  (block_comment)
  (comment)
] @comment

(tagged_union_kind name: (identifier) @keyword)

(tagged_union_binding tag: (identifier) @constant)

",," @operator

directive: ("#") @keyword ; #if
type: ("type_of") @type

(compiler_directive) @keyword
(heredoc_start) @none
(heredoc_end) @none
(heredoc_body) @string
(note) @string
