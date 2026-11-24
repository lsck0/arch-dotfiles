; extends

((new_expression
  constructor: (identifier) @_regex (#eq? @_regex "RegExp")
  arguments: (arguments
    (string
      (string_fragment) @injection.content)))
  (#set! injection.language "regex"))

((call_expression
  function: (member_expression
    property: (property_identifier) @_method
    (#any-of? @_method "match" "search" "replace" "replaceAll" "split"))
  arguments: (arguments
    (string
      (string_fragment) @injection.content)))
  (#set! injection.language "regex"))
