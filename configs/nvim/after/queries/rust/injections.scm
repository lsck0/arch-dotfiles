; extends

; query_as::<_, Type>("...") - generic function calls
(call_expression
  function: (generic_function
    function: (identifier) @_name (#match? @_name "^query"))
  arguments: (arguments
    (string_literal
      (string_content) @injection.content))
  (#set! injection.language "sql"))

(call_expression
  function: (generic_function
    function: (identifier) @_name (#match? @_name "^query"))
  arguments: (arguments
    (raw_string_literal
      (string_content) @injection.content))
  (#set! injection.language "sql"))

; query_as("...") - regular function calls  
(call_expression
  function: (identifier) @_name (#match? @_name "^query")
  arguments: (arguments
    (string_literal
      (string_content) @injection.content))
  (#set! injection.language "sql"))

(call_expression
  function: (identifier) @_name (#match? @_name "^query")
  arguments: (arguments
    (raw_string_literal
      (string_content) @injection.content))
  (#set! injection.language "sql"))

; sqlx::query_as::<_, Type>("...") with path
(call_expression
  function: (generic_function
    function: (scoped_identifier
      path: (identifier) @_path (#eq? @_path "sqlx")
      name: (identifier) @_name (#match? @_name "^query")))
  arguments: (arguments
    (string_literal
      (string_content) @injection.content))
  (#set! injection.language "sql"))

(call_expression
  function: (generic_function
    function: (scoped_identifier
      path: (identifier) @_path (#eq? @_path "sqlx")
      name: (identifier) @_name (#match? @_name "^query")))
  arguments: (arguments
    (raw_string_literal
      (string_content) @injection.content))
  (#set! injection.language "sql"))

; sqlx::query_as("...") without generics
(call_expression
  function: (scoped_identifier
    path: (identifier) @_path (#eq? @_path "sqlx")
    name: (identifier) @_name (#match? @_name "^query"))
  arguments: (arguments
    (string_literal
      (string_content) @injection.content))
  (#set! injection.language "sql"))

(call_expression
  function: (scoped_identifier
    path: (identifier) @_path (#eq? @_path "sqlx")
    name: (identifier) @_name (#match? @_name "^query"))
  arguments: (arguments
    (raw_string_literal
      (string_content) @injection.content))
  (#set! injection.language "sql"))

; ==================== REGEX HIGHLIGHTING ====================

; Regex::new(r"...") or Regex::new("...")
(call_expression
  function: (scoped_identifier
    path: (identifier) @_regex (#any-of? @_regex "Regex" "RegexBuilder")
    name: (identifier) @_new (#eq? @_new "new"))
  arguments: (arguments
    (raw_string_literal
      (string_content) @injection.content))
  (#set! injection.language "regex"))

(call_expression
  function: (scoped_identifier
    path: (identifier) @_regex (#any-of? @_regex "Regex" "RegexBuilder")
    name: (identifier) @_new (#eq? @_new "new"))
  arguments: (arguments
    (string_literal
      (string_content) @injection.content))
  (#set! injection.language "regex"))

; regex::Regex::new with path
(call_expression
  function: (scoped_identifier
    path: (scoped_identifier
      (identifier) @_regex (#any-of? @_regex "regex" "Regex")
      (identifier) @_type (#any-of? @_type "Regex" "RegexBuilder"))
    name: (identifier) @_new (#eq? @_new "new"))
  arguments: (arguments
    (raw_string_literal
      (string_content) @injection.content))
  (#set! injection.language "regex"))

(call_expression
  function: (scoped_identifier
    path: (scoped_identifier
      (identifier) @_regex (#any-of? @_regex "regex" "Regex")
      (identifier) @_type (#any-of? @_type "Regex" "RegexBuilder"))
    name: (identifier) @_new (#eq? @_new "new"))
  arguments: (arguments
    (string_literal
      (string_content) @injection.content))
  (#set! injection.language "regex"))

; RegexSet::new([...])
(call_expression
  function: (scoped_identifier
    path: (identifier) @_regex (#any-of? @_regex "RegexSet" "RegexSetBuilder")
    name: (identifier) @_new (#eq? @_new "new"))
  arguments: (arguments
    (array_expression
      (raw_string_literal
        (string_content) @injection.content)))
  (#set! injection.language "regex"))

; is_match, find, captures methods with regex string
(call_expression
  function: (field_expression
    value: (identifier)
    field: (field_identifier) @_method (#any-of? @_method "is_match" "find" "captures" "replace" "replace_all" "split"))
  arguments: (arguments
    (raw_string_literal
      (string_content) @injection.content))
  (#set! injection.language "regex"))
