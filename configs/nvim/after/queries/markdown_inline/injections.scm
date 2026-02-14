; extends

; LaTeX block math: $$...$$
((latex_block) @injection.content
  (#set! injection.language "latex")
  (#set! injection.include-children))
