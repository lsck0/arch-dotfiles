local M = {}

local function is_pointer_type(hover)
    if not hover or not hover.contents then
        return false
    end

    local text = ""

    local contents = hover.contents
    if type(contents) == "string" then
        text = contents
    elseif type(contents) == "table" then
        if contents.value then
            text = contents.value
        else
            for _, item in ipairs(contents) do
                if type(item) == "string" then
                    text = text .. item .. "\n"
                elseif item.value then
                    text = text .. item.value .. "\n"
                end
            end
        end
    end

    return text:match("%*") ~= nil
end

function M.dot()
    local ft = vim.bo.filetype
    if ft ~= "c" and ft ~= "cpp" then
        return "."
    end

    -- Only C/C++ reach here, and only if clangd is attached; otherwise a plain ".".
    local clients = vim.lsp.get_clients({ bufnr = 0, name = "clangd" })
    if #clients == 0 then
        return "."
    end
    -- Use clangd's own offset encoding (it runs utf-16), else columns are wrong.
    local params = vim.lsp.util.make_position_params(0, clients[1].offset_encoding)
    -- Short timeout: this blocks the UI on a very common keystroke, so cap the
    -- worst-case stall at 40ms and fall back to "." rather than hang.
    local responses = vim.lsp.buf_request_sync(
        0,
        "textDocument/hover",
        params,
        40
    )

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
