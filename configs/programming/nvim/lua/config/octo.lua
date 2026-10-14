local M = {}

-- from the private per-repo identity, never hardcoded
local function org()
    local o = vim.env.OCTO_DEFAULT_ORG
    if not o or o == "" then
        vim.notify("set OCTO_DEFAULT_ORG in .identity/env", vim.log.levels.WARN)
        return nil
    end
    return o
end

function M.org_cmd(fmt)
    local o = org()
    if o then
        vim.cmd(string.format(fmt, o))
    end
end

function M.org_search(filters)
    local o = org()
    if not o then
        return
    end
    local q = "org:" .. o .. " " .. filters
    require("octo.utils").create_base_search_command({ query = q })
end

return M
