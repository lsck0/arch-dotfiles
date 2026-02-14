; extends

; Fenced code blocks with language identifier - using standard pattern
(fenced_code_block
  (info_string
    (language) @injection.language)
  (code_fence_content) @injection.content)
