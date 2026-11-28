-- The cwd's persistence session, restored with a word when there is none or it fails: persistence.load returns
-- silently then and sources under silent!.

local M = {}

function M.load()
    local persistence = require("persistence")
    local file = vim.iter({ persistence.current(), persistence.current({ branch = false }) }):find(function(path)
        return vim.fn.filereadable(path) == 1
    end)
    if not file then
        return vim.notify("session: none for " .. vim.fn.fnamemodify(vim.fn.getcwd(), ":~"), vim.log.levels.WARN)
    end
    vim.v.errmsg = ""
    persistence.load()
    if vim.v.errmsg ~= "" then
        vim.notify("session: " .. vim.v.errmsg, vim.log.levels.WARN)
    end
end

return M
