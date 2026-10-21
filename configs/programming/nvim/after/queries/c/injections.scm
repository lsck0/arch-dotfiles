; extends

(call_expression
  function: (identifier) @_func (#eq? @_func "regcomp")
  arguments: (argument_list
    (_)
    (string_literal (string_content) @injection.content))
  (#set! injection.language "regex"))

(call_expression
  function: (identifier) @_func (#any-of? @_func "pcre_compile" "pcre2_compile")
  arguments: (argument_list
    (string_literal (string_content) @injection.content))
  (#set! injection.language "regex"))

(call_expression
  function: (identifier) @_func
  (#match? @_func "^(sqlite3_exec|sqlite3_get_table|sqlite3_prepare(16|_v2|_v3|16_v2|16_v3)?|nya_sql_exec|nya_sql_exec_bound)$")
  arguments: (argument_list
    (_)
    (string_literal (string_content) @injection.content))
  (#set! injection.language "sql"))

(call_expression
  function: (identifier) @_func (#any-of? @_func "nya_sql_query" "nya_orm_select")
  arguments: (argument_list
    (_)
    (_)
    (string_literal (string_content) @injection.content))
  (#set! injection.language "sql"))
