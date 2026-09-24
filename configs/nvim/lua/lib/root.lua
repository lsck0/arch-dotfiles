-- Resolve the git root to pin the file explorer to, so project.nvim chdir'ing into a nested crate (macros/, runner/) never re-roots the tree.
local M = {}

function M.git()
    local name = vim.api.nvim_buf_get_name(0)
    local start = name ~= "" and name or vim.uv.cwd()
    return vim.fs.root(start, ".git") or vim.uv.cwd()
end

return M
