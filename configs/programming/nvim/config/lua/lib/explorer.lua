-- The sidebar file tree (neo-tree): opened on a directory after a tcd, so the tree and the tab share one root.

local M = {}

local function command(args)
    require("neo-tree.command").execute(args)
end

-- Shows the tree for dir (else the cwd) beside the current window, keeping focus where it is.
---@param dir? string
function M.open(dir)
    dir = dir and vim.fs.normalize(dir) or vim.uv.cwd()
    pcall(vim.cmd.tcd, vim.fn.fnameescape(dir))
    command({ action = "show", source = "filesystem", position = "left", dir = dir })
end

function M.toggle()
    command({ toggle = true, source = "filesystem", position = "left", dir = vim.uv.cwd() })
end

return M
