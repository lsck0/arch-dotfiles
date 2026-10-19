--- blink.cmp source: citation keys inside \cite{...} (tex) and after @ (markdown). In tex texlab already completes
--- the keys of the project's own .bib files, so this adds only the Zotero export's.
local citation = require("lib.citation")

local source = {}

function source.new()
    return setmetatable({}, { __index = source })
end

function source:enabled()
    local filetype = vim.bo.filetype
    return citation.TEX_FILETYPES[filetype] or citation.MARKDOWN_FILETYPES[filetype] or false
end

function source:get_trigger_characters()
    return { "{", ",", "@" }
end

function source:get_completions(ctx, callback)
    local filetype = vim.bo[ctx.bufnr].filetype
    if not citation.in_cite(ctx.line:sub(1, ctx.cursor[2]), filetype) then
        callback({ items = {}, is_incomplete_forward = false, is_incomplete_backward = false })
        return
    end
    local zotero_only = citation.TEX_FILETYPES[filetype]
    local kind = require("blink.cmp.types").CompletionItemKind.Reference
    local items = {}
    for _, entry in ipairs(citation.entries(ctx.bufnr)) do
        if not zotero_only or entry.file == citation.ZOTERO_BIB then
            items[#items + 1] = {
                label = entry.key,
                kind = kind,
                insertText = entry.key,
                filterText = entry.key .. " " .. entry.author .. " " .. entry.title,
                labelDetails = { description = entry.author .. " " .. entry.year },
                documentation = {
                    kind = "markdown",
                    value = string.format("**%s**\n\n%s, %s", entry.title, entry.author, entry.year),
                },
            }
        end
    end
    callback({ items = items, is_incomplete_forward = false, is_incomplete_backward = false })
end

return source
