; extends

; new RegExp("...")
(new_expression
  constructor: (identifier) @_regex (#eq? @_regex "RegExp")
  arguments: (arguments
    (string
      (string_fragment) @injection.content)
    (#set! injection.language "regex")))

; /pattern/flags - regex literal
(regex_pattern) @injection.content
  (#set! injection.language "regex")

; string.match(/.../) or string.match("...")
(call_expression
  function: (member_expression
    object: (_)
    property: (property_identifier) @_method (#any-of? @_method "match" "search" "replace" "replaceAll" "split" "test" "exec"))
  arguments: (arguments
    (regex_pattern) @injection.content
    (#set! injection.language "regex")))

; Regex in string methods with string pattern
(call_expression
  function: (member_expression
    object: (_)
    property: (property_identifier) @_method (#any-of? @_method "match" "search" "replace" "replaceAll" "split"))
  arguments: (arguments
    (string
      (string_fragment) @injection.content)
    (#set! injection.language "regex")))

; String literal that looks like regex (contains regex special chars)
((string
  (string_fragment) @injection.content)
  (#match? @injection.content "^[\^\\.\\*\\+\\?\\$\\[\\(\\{\\|]")
  (#set! injection.language "regex"))
