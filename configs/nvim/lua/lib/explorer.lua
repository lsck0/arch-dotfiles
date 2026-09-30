-- tcd, then open without cwd: differing cwd forms stacked duplicate roots
local M = {}

function M.open()
    local root = require("lib.root").git()
    if root and root ~= "" then pcall(vim.cmd.tcd, vim.fn.fnameescape(root)) end
    require("snacks").explorer()
end

return M
