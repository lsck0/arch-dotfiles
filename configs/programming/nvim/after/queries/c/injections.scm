; extends

; POSIX regcomp(&re, "pattern", …) — pattern is the 2nd arg
(call_expression
  function: (identifier) @_func (#eq? @_func "regcomp")
  arguments: (argument_list
    (_)
    (string_literal (string_content) @injection.content))
  (#set! injection.language "regex"))

; PCRE pcre_compile("pattern", …) / pcre2_compile("pattern", …) — pattern is the 1st arg
(call_expression
  function: (identifier) @_func (#any-of? @_func "pcre_compile" "pcre2_compile")
  arguments: (argument_list
    (string_literal (string_content) @injection.content))
  (#set! injection.language "regex"))

; sqlite3 + nyangine calls with SQL as the 2nd arg (after a db handle)
(call_expression
  function: (identifier) @_func
  (#match? @_func "^(sqlite3_exec|sqlite3_get_table|sqlite3_prepare(16|_v2|_v3|16_v2|16_v3)?|nya_sql_exec|nya_sql_exec_bound)$")
  arguments: (argument_list
    (_)
    (string_literal (string_content) @injection.content))
  (#set! injection.language "sql"))

; nyangine calls with SQL as the 3rd arg (db, arena, "SQL")
(call_expression
  function: (identifier) @_func (#any-of? @_func "nya_sql_query" "nya_orm_select")
  arguments: (argument_list
    (_)
    (_)
    (string_literal (string_content) @injection.content))
  (#set! injection.language "sql"))
