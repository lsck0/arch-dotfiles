-- the local nyangine checkout's grammar, or false (require turns a nil module into true)
local grammar = vim.fn.expand("~/projects/nyangine/editors/tree-sitter-nya")
return vim.uv.fs_stat(grammar) and grammar or false
