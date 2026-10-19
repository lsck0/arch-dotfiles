; nyangine .nya object format, standard capture names so any colorscheme styles it

; header: `nya` magic, version and checksum are caught by (number)
"nya" @keyword

(member key: (identifier) @property)

; types: b8, u32, f32, string, object, array and the aliased array headers
(type) @type.builtin

(string) @string
(escape_sequence) @string.escape

(number) @number

(boolean) @boolean

(null) @constant.builtin

(comment) @comment @spell

[ "{" "}" "[" "]" ] @punctuation.bracket
[ ":" ";" "," ] @punctuation.delimiter
