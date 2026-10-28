local M = {}

local function is_pointer_type(hover)
    if not hover or not hover.contents then
        return false
    end

    local text = hover.contents.value or ""

    -- clangd puts the symbol's type on a "Type:" line; a `*` in template args or docs says nothing
    local line = ("\n" .. text):match("\nType: ([^\n]*)")
    if not line then
        return false
    end
    local ty = line:match("%(aka `([^`]+)`%)") or line:match("^`([^`]+)`") or line
    ty = ty:gsub("%b<>", "")
    local prev
    repeat
        prev = ty
        ty = ty:gsub("%s*&+$", ""):gsub("%s*const$", ""):gsub("%s*volatile$", ""):gsub("%s*restrict$", "")
    until ty == prev
    return ty:match("%*$") ~= nil
end

-- Only a dot after an identifier, `)` or `]`, outside comments and strings, can become `->`.
local function should_query_hover()
    local line = vim.api.nvim_get_current_line()
    local col = vim.api.nvim_win_get_cursor(0)[2]
    local prev_char = col > 0 and line:sub(col, col) or ""
    if not prev_char:match("[%w_%)%]]") then
        return false
    end
    local ok, node = pcall(vim.treesitter.get_node)
    if ok and node then
        local node_type = node:type()
        if node_type:find("comment") or node_type:find("string") then
            return false
        end
    end
    return true
end

function M.dot()
    local ft = vim.bo.filetype
    if ft ~= "c" and ft ~= "cpp" then
        return "."
    end

    local clients = vim.lsp.get_clients({ bufnr = 0, name = "clangd" })
    if #clients == 0 then
        return "."
    end

    if not should_query_hover() then
        return "."
    end
    -- clangd's own encoding (utf-16), else columns are off
    local params = vim.lsp.util.make_position_params(0, clients[1].offset_encoding)
    local responses = vim.lsp.buf_request_sync(0, "textDocument/hover", params, 40)

    if not responses then
        return "."
    end

    for _, resp in pairs(responses) do
        if is_pointer_type(resp.result) then
            return "->"
        end
    end

    return "."
end

function M.setup()
    vim.keymap.set("i", ".", function()
        return require("local_plugins.arrowdot").dot()
    end, { expr = true, silent = true })
end

return M
