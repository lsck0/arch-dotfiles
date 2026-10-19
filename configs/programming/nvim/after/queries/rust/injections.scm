; extends

; sqlx query builders, raw or normal strings: query("..."), query_as::<_, T>("..."), sqlx::query("...")
(call_expression
  function: [
    (identifier) @_name
    (scoped_identifier name: (identifier) @_name)
    (generic_function function: (identifier) @_name)
    (generic_function function: (scoped_identifier name: (identifier) @_name))
  ]
  (#match? @_name "^query")
  arguments: (arguments
    [
      (string_literal (string_content) @injection.content)
      (raw_string_literal (string_content) @injection.content)
    ])
  (#set! injection.language "sql"))

; Regex::new("...") with a non-raw string, upstream injects raw ones
(call_expression
  function: [
    (scoped_identifier
      path: (identifier) @_regex
      name: (identifier) @_new)
    (scoped_identifier
      path: (scoped_identifier (identifier) @_regex)
      name: (identifier) @_new)
  ]
  (#any-of? @_regex "Regex" "RegexBuilder")
  (#eq? @_new "new")
  arguments: (arguments
    (string_literal (string_content) @injection.content))
  (#set! injection.language "regex"))
