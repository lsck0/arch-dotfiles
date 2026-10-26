--- Citation keys from .bib files and the Zotero export, cached by mtime and size.

local M = {}

M.ZOTERO_BIB = vim.fs.joinpath(vim.env.XDG_DATA_HOME or vim.fs.normalize("~/.local/share"), "zotero", "library.bib")

local AUTHORS_SHOWN_MAX = 2
local SKIPPED_TYPES = { string = true, comment = true, preamble = true }
local TEX_FILETYPES = { tex = true, plaintex = true }
local MARKDOWN_FILETYPES = { markdown = true, quarto = true, rmd = true, pandoc = true }

---@class citation.Entry
---@field key string
---@field author string
---@field year string
---@field title string
---@field file string

---@type table<string, { mtime: integer, size: integer, entries: citation.Entry[] }>
local file_cache = {}
---@type table<integer, string[]>
local buffer_bibs = {}

---@param text string
---@return string
local function latex_strip(text)
    text = text:gsub("\\[%a]+%s*{", "{"):gsub("\\(.)", "%1"):gsub("[{}]", ""):gsub("%s+", " ")
    return vim.trim(text)
end

--- The value of FIELD in an entry body: a braced group, a quoted string or a bare word.
---@param body string
---@param body_lower string
---@param field string
---@return string?
local function field_get(body, body_lower, field)
    local eq
    local init = 1
    while not eq do
        local start, finish = body_lower:find(field, init, true)
        if not start then
            return nil
        end
        if body_lower:find("^[,%s]", start - 1) then
            eq = select(2, body_lower:find("^%s*=%s*", finish + 1))
        end
        init = finish + 1
    end
    local value = body:match("^%b{}", eq + 1) or body:match('^%b""', eq + 1)
    if value then
        return latex_strip(value:sub(2, -2))
    end
    return body:match("^[%w_]+", eq + 1)
end

---@param authors string
---@return string
local function authors_short(authors)
    local names = vim.split(authors, "%s+and%s+")
    local lasts = {}
    for i = 1, math.min(#names, AUTHORS_SHOWN_MAX) do
        local name = vim.trim(names[i])
        lasts[i] = name:match("^([^,]+),") or name:match("(%S+)$") or name
    end
    local text = table.concat(lasts, ", ")
    return #names > AUTHORS_SHOWN_MAX and text .. " et al." or text
end

---@param file string
---@param text string
---@return citation.Entry[]
local function bib_parse(file, text)
    local entries = {}
    local starts = {}
    local pos = text:find("@", 1, true)
    while pos do
        local kind, key = text:match("^@(%a+)%s*[{(]%s*([^,%s]+)%s*,", pos)
        if kind and not SKIPPED_TYPES[kind:lower()] then
            starts[#starts + 1] = { pos = pos, key = key }
        end
        pos = text:find("@", pos + 1, true)
    end
    for i, start in ipairs(starts) do
        local body = text:sub(start.pos, (starts[i + 1] and starts[i + 1].pos or #text + 1) - 1)
        local lower = body:lower()
        local year = field_get(body, lower, "year") or (field_get(body, lower, "date") or ""):match("%d%d%d%d") or ""
        entries[#entries + 1] = {
            key = start.key,
            author = authors_short(field_get(body, lower, "author") or field_get(body, lower, "editor") or ""),
            year = year,
            title = field_get(body, lower, "title") or "",
            file = file,
        }
    end
    return entries
end

---@param file string
---@return citation.Entry[]
local function bib_entries(file)
    local stat = vim.uv.fs_stat(file)
    if not stat then
        file_cache[file] = nil
        return {}
    end
    local cached = file_cache[file]
    if cached and cached.mtime == stat.mtime.sec and cached.size == stat.size then
        return cached.entries
    end
    local fd = io.open(file, "r")
    if not fd then
        return {}
    end
    local text = fd:read("*a")
    fd:close()
    local entries = bib_parse(file, text)
    file_cache[file] = { mtime = stat.mtime.sec, size = stat.size, entries = entries }
    return entries
end

---@param dir string
---@return string[]
local function bib_glob(dir)
    return vim.fn.globpath(dir, "*.bib", false, true)
end

--- The .bib files a buffer's document reads: vimtex's \bibliography and \addbibresource, else every .bib
--- next to the main file (tex) or the buffer and cwd (markdown).
---@param buf integer
---@return string[]
local function bibs_discover(buf)
    local files = {}
    if TEX_FILETYPES[vim.bo[buf].filetype] then
        local vimtex = vim.b[buf].vimtex
        if vimtex then
            vim.api.nvim_buf_call(buf, function()
                files = vim.fn["vimtex#bib#files"]()
            end)
        end
        if #files == 0 then
            files = bib_glob(vimtex and vimtex.root or vim.fs.dirname(vim.api.nvim_buf_get_name(buf)))
        end
    else
        files = bib_glob(vim.fs.dirname(vim.api.nvim_buf_get_name(buf)))
        vim.list_extend(files, bib_glob(vim.fn.getcwd()))
    end
    local seen, unique = {}, {}
    for _, file in ipairs(files) do
        local path = vim.fs.normalize(vim.fn.fnamemodify(file, ":p"))
        if not seen[path] and path ~= M.ZOTERO_BIB then
            seen[path] = true
            unique[#unique + 1] = path
        end
    end
    return unique
end

---@param buf integer
---@return string[]
local function bibs_get(buf)
    if not buffer_bibs[buf] then
        buffer_bibs[buf] = bibs_discover(buf)
        vim.api.nvim_create_autocmd({ "BufWritePost", "BufDelete" }, {
            buffer = buf,
            once = true,
            callback = function()
                buffer_bibs[buf] = nil
            end,
        })
    end
    return buffer_bibs[buf]
end

--- Every entry the buffer can cite, project files first; a key in both keeps the project's entry.
---@param buf integer
---@return citation.Entry[]
function M.entries(buf)
    local seen, result = {}, {}
    local files = vim.list_extend(vim.deepcopy(bibs_get(buf)), { M.ZOTERO_BIB })
    for _, file in ipairs(files) do
        for _, entry in ipairs(bib_entries(file)) do
            if not seen[entry.key] then
                seen[entry.key] = true
                result[#result + 1] = entry
            end
        end
    end
    return result
end

local TEX_CITE_PATTERN = "()\\%a*cite%a*%*?[^{}\\\n]-()%b{}()"
local MARKDOWN_CITE_PATTERN = "()%[[^%[%]]-@[^%[%]]-%]()"

--- The span of the cite command (tex) or bracketed citation (markdown) around COL, 1-based.
---@param line string
---@param col integer
---@param markdown boolean
---@return integer? close the column of the closing brace or bracket
local function cite_find(line, col, markdown)
    if markdown then
        for start, finish in line:gmatch(MARKDOWN_CITE_PATTERN) do
            if col >= start and col < finish then
                return finish - 1
            end
        end
        return nil
    end
    for start, _, finish in line:gmatch(TEX_CITE_PATTERN) do
        if col >= start and col < finish then
            return finish - 1
        end
    end
    return nil
end

--- Insert KEY at the cursor: into the cite under the cursor, else as a new one.
---@param key string
function M.insert(key)
    local buf = vim.api.nvim_get_current_buf()
    local filetype = vim.bo[buf].filetype
    local markdown = MARKDOWN_FILETYPES[filetype] or false
    local row, col0 = unpack(vim.api.nvim_win_get_cursor(0))
    local line = vim.api.nvim_get_current_line()
    local close = (TEX_FILETYPES[filetype] or markdown) and cite_find(line, col0 + 1, markdown)

    local text, at
    if close then
        local before = line:sub(1, close - 1)
        local inside = markdown and before:match("%[([^%[]*)$") or before:match("{([^{]*)$")
        local separator = vim.trim(inside) == "" and "" or (markdown and "; " or ",")
        text = separator .. (markdown and "@" or "") .. key
        at = close - 1
    else
        if markdown then
            text = "[@" .. key .. "]"
        elseif TEX_FILETYPES[filetype] then
            text = "\\cite{" .. key .. "}"
        else
            text = key
        end
        at = line == "" and 0 or col0 + 1
    end
    vim.api.nvim_buf_set_text(buf, row - 1, at, row - 1, at, { text })
    vim.api.nvim_win_set_cursor(0, { row, at + #text - 1 })
end

--- Pick an entry by key, author, year or title and insert its key.
function M.pick()
    local buf = vim.api.nvim_get_current_buf()
    local entries = M.entries(buf)
    if #entries == 0 then
        vim.notify("no .bib entries (project or " .. M.ZOTERO_BIB .. ")", vim.log.levels.WARN)
        return
    end
    local key_width = 0
    for _, entry in ipairs(entries) do
        key_width = math.max(key_width, #entry.key)
    end
    local items = {}
    for i, entry in ipairs(entries) do
        local display =
            string.format("%-" .. key_width .. "s  %-24s  %4s  %s", entry.key, entry.author, entry.year, entry.title)
        items[i] = { display = display, value = entry.key }
    end
    require("lib.pick").telescope("Citations", items, function(key)
        if key then
            M.insert(key)
        end
    end)
end

--- Whether the text before the cursor ends inside a cite's key list.
---@param before string
---@param filetype string
---@return boolean
function M.in_cite(before, filetype)
    if TEX_FILETYPES[filetype] then
        return before:match("\\%a*cite%a*%*?[^{}\\\n]-{[^}]*$") ~= nil
    end
    if MARKDOWN_FILETYPES[filetype] then
        return (before:match("^@[%w_:%-%.]*$") or before:match("[%s%[;%-]@[%w_:%-%.]*$")) ~= nil
    end
    return false
end

M.TEX_FILETYPES = TEX_FILETYPES
M.MARKDOWN_FILETYPES = MARKDOWN_FILETYPES

return M
