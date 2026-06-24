; extends

; regcomp(&regex, "pattern", flags) - POSIX regex
(call_expression
  function: (identifier) @_func (#eq? @_func "regcomp")
  arguments: (argument_list
    (_)  ; regex_t pointer
    (string_literal
      (string_content) @injection.content)
    (#set! injection.language "regex")))

; regcomp with raw string if using GNU extension (though C doesn't have raw strings)
; pcre_compile("pattern", ...) - PCRE library
(call_expression
  function: (identifier) @_func (#eq? @_func "pcre_compile")
  arguments: (argument_list
    (string_literal
      (string_content) @injection.content)
    (#set! injection.language "regex")))

; pcre2_compile for PCRE2
(call_expression
  function: (identifier) @_func (#eq? @_func "pcre2_compile")
  arguments: (argument_list
    (string_literal
      (string_content) @injection.content)
    (#set! injection.language "regex")))

; regexec(regex, "string", ...) - string parameter
(call_expression
  function: (identifier) @_func (#eq? @_func "regexec")
  arguments: (argument_list
    (_)  ; regex_t
    (string_literal
      (string_content) @injection.content)
    (#set! injection.language "regex")))

; sqlite3_exec(db, "SQL", callback, arg, errmsg) - SQL is 2nd arg
(call_expression
  function: (identifier) @_func (#eq? @_func "sqlite3_exec")
  arguments: (argument_list
    (_)  ; db handle
    (string_literal
      (string_content) @injection.content)
    (#set! injection.language "sql")))

; sqlite3_prepare / _v2 / _v3 / _16 (db, "SQL", ...) - SQL is 2nd arg
(call_expression
  function: (identifier) @_func (#match? @_func "^sqlite3_prepare(16|_v2|_v3|16_v2|16_v3)?$")
  arguments: (argument_list
    (_)  ; db handle
    (string_literal
      (string_content) @injection.content)
    (#set! injection.language "sql")))

; sqlite3_get_table(db, "SQL", ...) - SQL is 2nd arg
(call_expression
  function: (identifier) @_func (#eq? @_func "sqlite3_get_table")
  arguments: (argument_list
    (_)  ; db handle
    (string_literal
      (string_content) @injection.content)
    (#set! injection.language "sql")))
