-- git root, so a nested crate never re-roots the explorer
local M = {}

function M.git()
    local name = vim.api.nvim_buf_get_name(0)
    local start = name ~= "" and name or vim.uv.cwd()
    return vim.fs.root(start, ".git") or vim.uv.cwd()
end

return M
