; extends

; re.compile(r"...") and re.compile("...")
(call_expression
  function: (attribute
    object: (identifier) @_re (#eq? @_re "re")
    attribute: (identifier) @_func (#eq? @_func "compile"))
  arguments: (argument_list
    (string
      (string_content) @injection.content))
  (#set! injection.language "regex"))

; re.match(r"...", string) and re.match("...", string)
(call_expression
  function: (attribute
    object: (identifier) @_re (#eq? @_re "re")
    attribute: (identifier) @_func (#any-of? @_func "match" "search" "findall" "finditer" "split" "sub" "subn" "fullmatch"))
  arguments: (argument_list
    (string
      (string_content) @injection.content)
    (_))
  (#set! injection.language "regex"))

; pattern.match(string) - compiled regex methods
(call_expression
  function: (attribute
    object: (identifier)
    attribute: (identifier) @_method (#any-of? @_method "match" "search" "findall" "finditer" "split" "sub" "subn" "fullmatch"))
  arguments: (argument_list
    (string
      (string_content) @injection.content))
  (#set! injection.language "regex"))

; Regex in f-strings (for dynamic patterns)
; This is trickier but we can try to match re.compile inside f-strings
