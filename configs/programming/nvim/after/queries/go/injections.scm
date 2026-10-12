; extends

; database/sql Query/Exec/Prepare family with a string-literal SQL argument
(call_expression
  function: (selector_expression
    operand: (identifier)
    field: (field_identifier) @_field
    (#match? @_field "^(Query|QueryRow|Exec|ExecContext|QueryContext|QueryRowContext|Prepare|PrepareContext)$"))
  arguments: (argument_list
    [
      (raw_string_literal) @injection.content
      (interpreted_string_literal) @injection.content
    ])
  (#set! injection.language "sql")
  (#offset! @injection.content 0 1 0 -1))
