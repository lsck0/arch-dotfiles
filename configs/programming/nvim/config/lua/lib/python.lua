-- the project's python interpreter, one resolution order for every consumer (pyright, dap)

local M = {}

local POETRY_TIMEOUT_S = "2"

---@param root any the project root; a json-null rootPath is vim.NIL, which is truthy
---@return string? python $VIRTUAL_ENV's, else root/.venv's, else the poetry env's; nil when none resolves
function M.find(root)
    if type(root) ~= "string" or root == "" then
        return nil
    end
    local venv = vim.env.VIRTUAL_ENV
    if venv and vim.fn.executable(venv .. "/bin/python") == 1 then
        return venv .. "/bin/python"
    end
    if vim.fn.executable(root .. "/.venv/bin/python") == 1 then
        return root .. "/.venv/bin/python"
    end
    if vim.fn.filereadable(root .. "/pyproject.toml") == 1 and vim.fn.executable("poetry") == 1 then
        local out = vim.trim(vim.fn.system({ "timeout", POETRY_TIMEOUT_S, "poetry", "-C", root, "env", "info", "-e" }))
        if vim.v.shell_error == 0 and out ~= "" then
            return out
        end
    end
end

return M
