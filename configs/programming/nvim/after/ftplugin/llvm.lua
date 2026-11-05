-- LLVM IR (.ll): nvim's own filetype and the treesitter llvm parser; :make runs the verifier, :Llc and :Opt show the
-- lowered assembly or an optimized module in a scratch split
vim.bo.commentstring = "; %s"
vim.bo.comments = ":;"
vim.bo.makeprg = "opt -passes=verify -disable-output %"
vim.bo.errorformat = "opt: %f:%l:%c: %trror: %m,%-G%.%#"

---@param cmd string[]
local function scratch(cmd)
    local result = vim.system(cmd, { stdin = vim.api.nvim_buf_get_lines(0, 0, -1, false) }):wait()
    local out = result.code == 0 and result.stdout or result.stderr
    vim.cmd("vnew")
    vim.bo.buftype = "nofile"
    vim.bo.bufhidden = "wipe"
    vim.bo.filetype = result.code == 0 and cmd[1] == "opt" and "llvm" or "asm"
    vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(out or "", "\n", { trimempty = true }))
end

vim.api.nvim_buf_create_user_command(0, "Llc", function(o)
    scratch(vim.list_extend({ "llc", "-o", "-" }, o.fargs))
end, { nargs = "*", desc = "llc the buffer (extra args: -O2, -mtriple=...), assembly in a split" })
vim.api.nvim_buf_create_user_command(0, "Opt", function(o)
    local args = #o.fargs > 0 and o.fargs or { "-O2" }
    scratch(vim.list_extend(vim.list_extend({ "opt", "-S" }, args), { "-o", "-" }))
end, { nargs = "*", desc = "opt the buffer (default -O2, or -passes=...), the module in a split" })
