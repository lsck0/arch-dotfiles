; extends

; db.Query, db.QueryRow, db.Exec with raw string literal
(call_expression
  function: (selector_expression
    operand: (identifier)
    field: (field_identifier) @_field (#match? @_field "^(Query|QueryRow|Exec|ExecContext|QueryContext|QueryRowContext)$"))
  arguments: (argument_list
    (raw_string_literal) @injection.content)
  (#set! injection.language "sql")
  (#offset! @injection.content 0 1 0 -1))

; db.Query, db.QueryRow, db.Exec with interpreted string literal
(call_expression
  function: (selector_expression
    operand: (identifier)
    field: (field_identifier) @_field (#match? @_field "^(Query|QueryRow|Exec|ExecContext|QueryContext|QueryRowContext)$"))
  arguments: (argument_list
    (interpreted_string_literal) @injection.content)
  (#set! injection.language "sql")
  (#offset! @injection.content 0 1 0 -1))

; stmt.Query, stmt.QueryRow, etc. (prepared statements)
(call_expression
  function: (selector_expression
    operand: (identifier)
    field: (field_identifier) @_field (#match? @_field "^(Query|QueryRow|Exec|ExecContext|QueryContext|QueryRowContext|Prepare|PrepareContext)$"))
  arguments: (argument_list
    (raw_string_literal) @injection.content)
  (#set! injection.language "sql")
  (#offset! @injection.content 0 1 0 -1))

(call_expression
  function: (selector_expression
    operand: (identifier)
    field: (field_identifier) @_field (#match? @_field "^(Query|QueryRow|Exec|ExecContext|QueryContext|QueryRowContext|Prepare|PrepareContext)$"))
  arguments: (argument_list
    (interpreted_string_literal) @injection.content)
  (#set! injection.language "sql")
  (#offset! @injection.content 0 1 0 -1))
