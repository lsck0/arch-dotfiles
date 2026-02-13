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
