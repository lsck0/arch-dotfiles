-- GitHub Projects V2 board driven by the project's saved views; org + number from OCTO_DEFAULT_ORG/PROJECT.
local M = {}

local COL_WIDTH = 30          -- board column display width
local LIST_WIDTH = 70         -- list-view title truncation
local TITLE_WIDTH = 46        -- table title column
local FIELD_WIDTH_MAX = 24    -- other table columns shrink to their widest value
local LEFT = "  "             -- left margin on grid lines
local SEP = " │ "             -- between board columns
local GAP = "  "              -- between table columns
local NS = vim.api.nvim_create_namespace("ghproject")
local LEGEND =
    "hjkl move · H/L status · J/K reorder · ⇥ view · v layout · p/P project · / search · e edit · ⏎ open · r refresh · q quit"

local LAYOUTS = { BOARD_LAYOUT = "board", TABLE_LAYOUT = "table", ROADMAP_LAYOUT = "table" } -- no roadmap in a terminal
local LAYOUT_CYCLE = { "board", "table", "list" }
local DEFAULT_VIEW = { name = "Board", layout = "BOARD_LAYOUT", filter = "", fields = {}, sort = {}, vgroup = "Status" }
local KEY_ALIASES = { assignee = "assignees", label = "labels", reviewer = "reviewers", repo = "repository" }
local IS_TYPES = { issue = "Issue", pr = "PullRequest", ["pull-request"] = "PullRequest", draft = "DraftIssue" }

-- module state
local state = nil        -- current board, see fetch() for its fields
local cache = {}         -- ["org/num"] = state, so reopening renders before the refresh lands
local projects = nil     -- [{number, title}] for the org, fetched once
local projects_org = nil -- the org `projects` was fetched for
local proj_idx = 1       -- current index into `projects`
local cur_org = nil      -- org of the open board
local board_buf = nil    -- the reusable board buffer
local views_warned = {}  -- ["org/num"] = true once a failed views fetch was reported

-- persistent cache: survives restarts and avoids refetching (and gh rate limits)
local CACHE_DIR = vim.fn.stdpath("cache") .. "/ghproject"
local CACHE_VERSION = 3 -- bump when the disk format changes
local TTL = 300 -- seconds; a cache younger than this skips the background refresh
local ITEM_LIMIT = "5000" -- gh pages 100 per request; views filter client-side, so every item must be loaded

local function cache_path(key) return CACHE_DIR .. "/" .. key:gsub("[^%w]", "_") .. ".json" end

local function disk_read(key)
    local f = io.open(cache_path(key), "r")
    if not f then return nil end
    local raw = f:read("*a"); f:close()
    local ok, d = pcall(vim.json.decode, raw, { luanil = { object = true, array = true } })
    return ok and d or nil
end

local function disk_write(key, obj)
    vim.fn.mkdir(CACHE_DIR, "p")
    local f = io.open(cache_path(key), "w")
    if not f then return end
    f:write(vim.json.encode(obj)); f:close()
end

local function warn(msg) vim.notify("ghproject: " .. msg, vim.log.levels.WARN) end
local function err(msg) vim.notify("ghproject: " .. msg, vim.log.levels.ERROR) end

-- run gh with the inherited identity env; cb(ok, decoded_json_or_stderr)
local function gh_json(args, cb)
    vim.system({ "gh", unpack(args) }, { text = true, cwd = vim.fn.getcwd() }, function(res)
        vim.schedule(function()
            if res.code ~= 0 then
                cb(false, (res.stderr ~= "" and res.stderr) or "gh exited " .. res.code)
                return
            end
            local ok, decoded = pcall(vim.json.decode, res.stdout, { luanil = { object = true, array = true } })
            if not ok then
                cb(false, "bad json from gh")
                return
            end
            cb(true, decoded)
        end)
    end)
end

-- resolve a highlight group, falling back to a builtin when the ftplugin has not defined it
local function grp(name, fallback)
    return vim.fn.hlexists(name) == 1 and name or fallback
end

local function header_group(i)
    local g = "GhProjectHeader" .. ((i - 1) % 7 + 1)
    if vim.fn.hlexists(g) == 1 then return g end
    return grp("GhProjectHeader", "Title")
end

-- truncate to a DISPLAY width (emoji/wide glyphs count as 2), so columns align
local function truncate(s, n)
    s = tostring(s or ""):gsub("[\r\n]", " ")
    if vim.fn.strdisplaywidth(s) <= n then return s end
    local out, w = "", 0
    for _, ch in ipairs(vim.fn.split(s, "\\zs")) do
        local cw = vim.fn.strdisplaywidth(ch)
        if w + cw > n - 1 then break end
        out, w = out .. ch, w + cw
    end
    return out .. "…"
end

-- pad to a fixed DISPLAY width (variable bytes), truncating first
local function pad(s, n)
    s = truncate(s, n)
    return s .. string.rep(" ", n - vim.fn.strdisplaywidth(s))
end

local function cell(text) return pad(text, COL_WIDTH) end

local function card_text(card)
    return card and string.format("#%s  %s", card.number or "-", card.title) or ""
end

local function join(cells) return table.concat(cells, SEP) end

-- byte ranges {start, stop} of each cell inside `base .. cells joined by a seplen-byte sep`
local function ranges(cells, base, seplen)
    local r, pos = {}, base
    for i, c in ipairs(cells) do
        r[i] = { pos, pos + #c }
        pos = pos + #c + seplen
    end
    return r
end

local function board_header_cells(columns)
    local t = {}
    for i, c in ipairs(columns) do t[i] = cell(string.format("%s  (%d)", c.name, #c.cards)) end
    return t
end

local function board_row_cells(columns, row)
    local t = {}
    for i, c in ipairs(columns) do t[i] = cell(card_text(c.cards[row])) end
    return t
end

local function rule_line(columns)
    local segs = {}
    for i = 1, #columns do segs[i] = string.rep("─", COL_WIDTH) end
    return table.concat(segs, "─┼─")
end

-- fields ---------------------------------------------------------------------

-- filter keys compare lowercased with spaces as hyphens ("target-date")
local function norm(name) return (tostring(name or ""):lower():gsub("%s+", "-")) end

local function field_by_name(fields, name)
    if not name then return nil end
    for _, f in ipairs(fields) do
        if f.name:lower() == name:lower() then return f end
    end
end

local function field_by_key(fields, key)
    key = norm(key)
    key = KEY_ALIASES[key] or key
    for _, f in ipairs(fields) do
        if norm(f.name) == key then return f end
    end
end

-- a card's value for a field as lowercase strings, one per list entry
local function card_values(card, field_name)
    local lname = field_name:lower()
    if lname == "title" then return { card.title:lower() } end
    if lname == "repository" then
        local full = card.repo_full:lower()
        return full ~= "" and { full, card.repo:lower() } or {}
    end
    local v = card.raw and card.raw[lname]
    if v == nil or v == "" then return {} end
    if type(v) ~= "table" then return { tostring(v):lower() } end
    if v.title then return { tostring(v.title):lower() } end
    local out = {}
    for _, e in ipairs(v) do
        local s = type(e) == "table" and (e.title or e.login or e.name) or e
        if s then out[#out + 1] = tostring(s):lower() end
    end
    return out
end

local function card_display(card, field_name)
    local lname = field_name:lower()
    if lname == "title" then return card.title end
    if lname == "repository" then return card.repo end
    local v = card.raw and card.raw[lname]
    if type(v) ~= "table" then return v ~= nil and tostring(v) or "" end
    if v.title then return tostring(v.title) end
    local out = {}
    for _, e in ipairs(v) do out[#out + 1] = type(e) == "table" and (e.title or e.login or e.name or "") or tostring(e) end
    return table.concat(out, ", ")
end

-- filter ---------------------------------------------------------------------

local function match_card(card, q)
    return ((card.title or ""):lower():find(q, 1, true) ~= nil)
        or (("#" .. tostring(card.number or "")):lower():find(q, 1, true) ~= nil)
        or ((card.repo or ""):lower():find(q, 1, true) ~= nil)
end

local function tokenize(s)
    local out, cur, quoted = {}, {}, false
    for ch in s:gmatch(".") do
        if ch == '"' then quoted = not quoted end
        if ch:match("%s") and not quoted then
            if #cur > 0 then out[#out + 1] = table.concat(cur); cur = {} end
        else
            cur[#cur + 1] = ch
        end
    end
    if #cur > 0 then out[#out + 1] = table.concat(cur) end
    return out
end

-- comma-separated values as {text, quoted}; quoted values match literally
local function split_values(s)
    local out, cur, quoted, was_quoted = {}, {}, false, false
    for ch in s:gmatch(".") do
        if ch == '"' then
            quoted, was_quoted = not quoted, true
        elseif ch == "," and not quoted then
            out[#out + 1] = { text = table.concat(cur), quoted = was_quoted }
            cur, was_quoted = {}, false
        else
            cur[#cur + 1] = ch
        end
    end
    out[#out + 1] = { text = table.concat(cur), quoted = was_quoted }
    return out
end

local function cmp(a, b)
    local na, nb = tonumber(a), tonumber(b)
    if na and nb then a, b = na, nb end
    return a < b and -1 or (a > b and 1 or 0)
end

local function value_matcher(spec)
    local lo, hi = spec:match("^(.-)%.%.(.*)$")
    if lo then
        return function(v)
            return (lo == "" or lo == "*" or cmp(v, lo) >= 0) and (hi == "" or hi == "*" or cmp(v, hi) <= 0)
        end
    end
    local op, rest = spec:match("^([<>]=?)(.+)$")
    if op then
        return function(v)
            local c = cmp(v, rest)
            if op == ">" then return c > 0 elseif op == ">=" then return c >= 0 elseif op == "<" then return c < 0 end
            return c <= 0
        end
    end
    if spec:find("*", 1, true) then
        local pat = "^" .. spec:gsub("[%^%$%(%)%%%.%[%]%+%-%?]", "%%%0"):gsub("%*", ".*") .. "$"
        return function(v) return v:find(pat) ~= nil end
    end
    return function(v) return v == spec end
end

-- @current/@next/@previous as an iteration title, from the iteration dates the cards carry
local function iteration_title(s, field, which)
    local its, seen, lname = {}, {}, field.name:lower()
    for _, card in ipairs(s.cards) do
        local it = card.raw and card.raw[lname]
        if type(it) == "table" and it.startDate and not seen[it.startDate] then
            seen[it.startDate] = true
            its[#its + 1] = it
        end
    end
    table.sort(its, function(a, b) return a.startDate < b.startDate end)
    local today, cur = os.date("%Y-%m-%d"), 0
    for i, it in ipairs(its) do
        if it.startDate <= today then cur = i end
    end
    local it = its[cur + ({ ["@current"] = 0, ["@next"] = 1, ["@previous"] = -1 })[which]]
    return it and tostring(it.title):lower() or nil
end

-- one filter token as a card predicate, nil when this client cannot evaluate it
local function compile_token(s, token)
    local neg = token:sub(1, 1) == "-"
    local body = neg and token:sub(2) or token
    local key, rest = body:match('^([%w%-_ "]+):(.+)$')
    local pred
    if not key then
        local q = body:gsub('"', ""):lower()
        pred = function(card) return match_card(card, q) end
    else
        key = norm((key:gsub('"', "")))
        local values = split_values(rest)
        if key == "is" then
            local types = {}
            for _, v in ipairs(values) do
                local t = IS_TYPES[v.text:lower()]
                if not t then return nil end -- open/closed/merged: gh item-list carries no state
                types[t] = true
            end
            pred = function(card) return types[card.type] == true end
        elseif key == "no" or key == "has" then
            local f = field_by_key(s.fields, values[1].text)
            if not f then return nil end
            local want = key == "has"
            pred = function(card) return (#card_values(card, f.name) > 0) == want end
        else
            local f = field_by_key(s.fields, key)
            if not f then return nil end
            local matchers = {}
            for _, v in ipairs(values) do
                local text = v.text:lower()
                if text == "@me" then text = (s.viewer or ""):lower() end
                text = text:gsub("@today", os.date("%Y-%m-%d"))
                if text == "@current" or text == "@next" or text == "@previous" then
                    local title = iteration_title(s, f, text)
                    matchers[#matchers + 1] = function(cv) return cv == title end
                elseif v.quoted then
                    matchers[#matchers + 1] = function(cv) return cv == text end
                else
                    matchers[#matchers + 1] = value_matcher(text)
                end
            end
            pred = function(card)
                for _, cv in ipairs(card_values(card, f.name)) do
                    for _, m in ipairs(matchers) do
                        if m(cv) then return true end
                    end
                end
                return false
            end
        end
    end
    if neg then return function(card) return not pred(card) end end
    return pred
end

-- tokens AND together; returns the predicate and the tokens it had to ignore
local function compile_filter(s, filter)
    local preds, ignored = {}, {}
    for _, token in ipairs(tokenize(filter or "")) do
        local p = compile_token(s, token)
        if p then preds[#preds + 1] = p else ignored[#ignored + 1] = token end
    end
    return function(card)
        for _, p in ipairs(preds) do
            if not p(card) then return false end
        end
        return true
    end, ignored
end

-- views ----------------------------------------------------------------------

local function compile_view(s, raw)
    local pred, ignored = compile_filter(s, raw.filter)
    local col = field_by_name(s.fields, raw.vgroup)
    if not col or col.type ~= "ProjectV2SingleSelectField" then col = field_by_name(s.fields, "Status") end
    local sort = {}
    for _, k in ipairs(raw.sort or {}) do
        local f = field_by_name(s.fields, k.name)
        if f then sort[#sort + 1] = { field = f, desc = k.desc } end
    end
    return {
        name = raw.name,
        layout = LAYOUTS[raw.layout] or "board",
        pred = pred,
        ignored = ignored,
        col_field = col,
        group_field = field_by_name(s.fields, raw.group),
        sort = sort,
        table_fields = raw.fields or {},
    }
end

-- the api ignores tab order, so OCTO_DEFAULT_VIEWS ("18,1,4") lists view numbers first for the default project
local function ordered_views(s)
    if #s.views == 0 then return { DEFAULT_VIEW } end
    if tostring(s.num) ~= vim.env.OCTO_DEFAULT_PROJECT then return s.views end
    local rank = {}
    for i, n in ipairs(vim.split(vim.env.OCTO_DEFAULT_VIEWS or "", ",", { trimempty = true })) do rank[tonumber(n)] = i end
    local out = vim.list_slice(s.views)
    local pos = {}
    for i, v in ipairs(out) do pos[v] = i end
    table.sort(out, function(a, b)
        local ra, rb = rank[a.number] or math.huge, rank[b.number] or math.huge
        if ra ~= rb then return ra < rb end
        return pos[a] < pos[b]
    end)
    return out
end

local function prepare(s)
    s.cviews = {}
    for _, raw in ipairs(ordered_views(s)) do s.cviews[#s.cviews + 1] = compile_view(s, raw) end
    if s.view_idx > #s.cviews then s.view_idx = 1 end
    s.layout = s.layout or s.cviews[s.view_idx].layout
    s.vis, s.vc, s.rows = nil, nil, nil
end

local function cur_view() return state.cviews[state.view_idx] end

local function invalidate() state.vis, state.vc, state.rows = nil, nil, nil end

-- option position for single selects, number when numeric, else the lowercase text
local function sort_key(card, field)
    local v = card_values(card, field.name)[1]
    if v == nil then return nil end
    for i, o in ipairs(field.options) do
        if o.name:lower() == v then return i end
    end
    return tonumber(v) or v
end

-- cards the view and search show, in view sort order (project position when unsorted)
local function visible()
    if state.vis then return state.vis end
    local view, q = cur_view(), state.filter and state.filter:lower()
    local out = {}
    for _, card in ipairs(state.cards) do
        if view.pred(card) and (not q or match_card(card, q)) then out[#out + 1] = card end
    end
    if #view.sort > 0 then
        local pos = {}
        for i, card in ipairs(out) do pos[card] = i end
        table.sort(out, function(a, b)
            for _, k in ipairs(view.sort) do
                local ka, kb = sort_key(a, k.field), sort_key(b, k.field)
                if type(ka) ~= type(kb) and ka ~= nil and kb ~= nil then ka, kb = tostring(ka), tostring(kb) end
                if ka ~= kb then
                    if ka == nil then return false end
                    if kb == nil then return true end
                    if k.desc then return ka > kb end
                    return ka < kb
                end
            end
            return pos[a] < pos[b]
        end)
    end
    state.vis = out
    return out
end

-- "No <field>" first (dropped when empty), then options in order or values as first seen
local function group_by(cards, field)
    local none = { name = "No " .. field.name, cards = {} }
    local groups, by_name = { none }, {}
    for _, o in ipairs(field.options) do
        local g = { name = o.name, opt_id = o.id, cards = {} }
        groups[#groups + 1] = g
        by_name[o.name:lower()] = g
    end
    for _, card in ipairs(cards) do
        local v = card_display(card, field.name)
        local g = none
        if v ~= "" then
            g = by_name[v:lower()]
            if not g then
                g = { name = v, cards = {} }
                groups[#groups + 1] = g
                by_name[v:lower()] = g
            end
        end
        g.cards[#g.cards + 1] = card
    end
    if #none.cards == 0 then table.remove(groups, 1) end
    return groups
end

local function vcols()
    state.vc = state.vc or group_by(visible(), cur_view().col_field)
    return state.vc
end

-- table/list rows as groups; one unnamed group for an ungrouped table
local function row_groups()
    if state.rows then return state.rows end
    local view = cur_view()
    local field = view.group_field or (state.layout == "list" and view.col_field) or nil
    state.rows = field and group_by(visible(), field) or { { cards = visible() } }
    return state.rows
end

local function flat_visible()
    local out = {}
    for _, g in ipairs(row_groups()) do
        for _, card in ipairs(g.cards) do out[#out + 1] = card end
    end
    return out
end

-- selection helpers ----------------------------------------------------------

local function selected()
    if state.layout == "board" then
        local c = vcols()[state.cur.col]
        return c and c.cards[state.cur.row]
    end
    return flat_visible()[state.frow]
end

local function board_pos(card)
    for ci, c in ipairs(vcols()) do
        for ri, k in ipairs(c.cards) do
            if k == card then return ci, ri end
        end
    end
    return 1, 1
end

local function flat_index(card)
    for i, k in ipairs(flat_visible()) do
        if k == card then return i end
    end
    return 1
end

local function follow(card)
    state.cur.col, state.cur.row = board_pos(card)
    state.frow = flat_index(card)
end

local function clamp_all()
    local vc = vcols()
    state.cur.col = math.max(1, math.min(state.cur.col, math.max(#vc, 1)))
    local n = vc[state.cur.col] and #vc[state.cur.col].cards or 0
    state.cur.row = math.max(1, math.min(state.cur.row, math.max(n, 1)))
    local nf = #flat_visible()
    state.frow = math.max(1, math.min(state.frow, math.max(nf, 1)))
end

-- rendering ------------------------------------------------------------------

local function table_columns(cards)
    local names = cur_view().table_fields
    if #names == 0 then names = { "Title", "Status", "Priority", "Size", "Repository" } end
    local cols = { { name = "#", w = 7, get = function(c) return "#" .. (c.number or "-") end } }
    for _, name in ipairs(names) do
        if name == "Title" then
            cols[#cols + 1] = { name = name, w = TITLE_WIDTH, get = function(c) return c.title end }
        else
            local w = vim.fn.strdisplaywidth(name)
            for _, c in ipairs(cards) do w = math.max(w, vim.fn.strdisplaywidth(card_display(c, name))) end
            cols[#cols + 1] = { name = name, w = math.min(w, FIELD_WIDTH_MAX), get = function(c) return card_display(c, name) end }
        end
    end
    return cols
end

local function render_header(lines, marks)
    local n = projects and #projects or 1
    local h = string.format("  %s  [%d/%d]  · %s  · %d items", state.title or "", state.idx, n, state.layout, #visible())
    if state.filter then h = h .. "  · search: " .. state.filter end
    local ignored = cur_view().ignored
    if #ignored > 0 then h = h .. "  · ignored: " .. table.concat(ignored, " ") end
    lines[#lines + 1] = h
    marks[#marks + 1] = { grp("GhProjectTitle", "Title"), #lines - 1, 0, -1 }

    local line, tabs = LEFT, {}
    for i, v in ipairs(state.cviews) do
        local label = " " .. v.name .. " "
        tabs[i] = { #line, #line + #label }
        line = line .. label .. (i < #state.cviews and "│" or "")
    end
    lines[#lines + 1] = line
    for i, r in ipairs(tabs) do
        local g = i == state.view_idx and grp("GhProjectSel", "Visual") or grp("GhProjectHint", "Comment")
        marks[#marks + 1] = { g, #lines - 1, r[1], r[2] }
    end

    lines[#lines + 1] = "  " .. LEGEND
    marks[#marks + 1] = { grp("GhProjectHint", "Comment"), #lines - 1, 0, -1 }
end

local function render_board(lines, marks)
    local vc = vcols()
    local hcells = board_header_cells(vc)
    lines[#lines + 1] = LEFT .. join(hcells)
    local hln = #lines - 1
    local hr = ranges(hcells, #LEFT, #SEP)
    for i = 1, #vc do marks[#marks + 1] = { header_group(i), hln, hr[i][1], hr[i][2] } end
    for i = 1, #vc - 1 do marks[#marks + 1] = { grp("GhProjectSep", "Comment"), hln, hr[i][2], hr[i + 1][1] } end

    lines[#lines + 1] = LEFT .. rule_line(vc)
    marks[#marks + 1] = { grp("GhProjectSep", "Comment"), #lines - 1, 0, -1 }

    local first = #lines -- 0-based line index preceding the first card row
    local maxr = 1
    for _, c in ipairs(vc) do maxr = math.max(maxr, #c.cards) end
    for row = 1, maxr do
        local cells = board_row_cells(vc, row)
        lines[#lines + 1] = LEFT .. join(cells)
        local ln = #lines - 1
        local cr = ranges(cells, #LEFT, #SEP)
        for col = 1, #vc do
            local card = vc[col].cards[row]
            if card then
                if col == state.cur.col and row == state.cur.row then
                    marks[#marks + 1] = { grp("GhProjectSel", "Visual"), ln, cr[col][1], cr[col][2] }
                elseif col ~= state.cur.col then
                    marks[#marks + 1] = { grp("GhProjectDim", "Comment"), ln, cr[col][1], cr[col][2] }
                end
            end
        end
        for col = 1, #vc - 1 do marks[#marks + 1] = { grp("GhProjectSep", "Comment"), ln, cr[col][2], cr[col + 1][1] } end
    end

    local sel = vc[state.cur.col] and vc[state.cur.col].cards[state.cur.row]
    if sel then
        local cr = ranges(board_row_cells(vc, state.cur.row), #LEFT, #SEP)
        return { first + state.cur.row, cr[state.cur.col][1] }
    end
end

local function render_table(lines, marks)
    local cols = table_columns(flat_visible())
    local hcells = {}
    for i, tc in ipairs(cols) do hcells[i] = pad(tc.name, tc.w) end
    lines[#lines + 1] = LEFT .. table.concat(hcells, GAP)
    local hln, hr = #lines - 1, ranges(hcells, #LEFT, #GAP)
    for i = 1, #cols do marks[#marks + 1] = { header_group(i), hln, hr[i][1], hr[i][2] } end

    local total = (#cols - 1) * vim.fn.strdisplaywidth(GAP)
    for _, tc in ipairs(cols) do total = total + tc.w end
    lines[#lines + 1] = LEFT .. string.rep("─", total)
    marks[#marks + 1] = { grp("GhProjectSep", "Comment"), #lines - 1, 0, -1 }

    local idx, cursor = 0, nil
    for gi, g in ipairs(row_groups()) do
        if g.name and #g.cards > 0 then
            lines[#lines + 1] = string.format("  %s  (%d)", g.name, #g.cards)
            marks[#marks + 1] = { header_group(gi), #lines - 1, 0, -1 }
        end
        for _, card in ipairs(g.cards) do
            idx = idx + 1
            local cells = {}
            for j, tc in ipairs(cols) do cells[j] = pad(tc.get(card), tc.w) end
            lines[#lines + 1] = LEFT .. table.concat(cells, GAP)
            if idx == state.frow then
                marks[#marks + 1] = { grp("GhProjectSel", "Visual"), #lines - 1, 0, -1 }
                cursor = { #lines, #LEFT }
            end
        end
    end
    return cursor
end

local function render_list(lines, marks)
    local idx, cursor, first = 0, nil, true
    for gi, g in ipairs(row_groups()) do
        if #g.cards > 0 then
            if not first then lines[#lines + 1] = "" end
            first = false
            if g.name then
                lines[#lines + 1] = string.format("  %s  (%d)", g.name, #g.cards)
                marks[#marks + 1] = { header_group(gi), #lines - 1, 0, -1 }
            end
            for _, card in ipairs(g.cards) do
                idx = idx + 1
                lines[#lines + 1] = string.format("    #%s  %s", card.number or "-", truncate(card.title, LIST_WIDTH))
                if idx == state.frow then
                    marks[#marks + 1] = { grp("GhProjectSel", "Visual"), #lines - 1, 0, -1 }
                    cursor = { #lines, 0 }
                end
            end
        end
    end
    return cursor
end

local function redraw()
    local s = state
    if not s or not vim.api.nvim_buf_is_valid(s.buf) then return end
    clamp_all()

    local lines, marks = {}, {}
    render_header(lines, marks)
    local cursor
    if s.layout == "table" then
        cursor = render_table(lines, marks)
    elseif s.layout == "list" then
        cursor = render_list(lines, marks)
    else
        cursor = render_board(lines, marks)
    end

    vim.bo[s.buf].modifiable = true
    vim.api.nvim_buf_set_lines(s.buf, 0, -1, false, lines)
    vim.bo[s.buf].modifiable = false

    vim.api.nvim_buf_clear_namespace(s.buf, NS, 0, -1)
    for _, m in ipairs(marks) do
        local group, l, a, b = m[1], m[2], m[3], m[4]
        local opts = { hl_group = group, end_row = l }
        if b == -1 then
            opts.end_col, opts.hl_eol = #(lines[l + 1] or ""), true
        else
            opts.end_col = b
        end
        pcall(vim.api.nvim_buf_set_extmark, s.buf, NS, l, a, opts)
    end

    -- keep the selection on screen: place the cursor on it, then centre
    local win = vim.fn.bufwinid(s.buf)
    if win ~= -1 and cursor then
        pcall(vim.api.nvim_win_set_cursor, win, { cursor[1], cursor[2] })
        pcall(vim.api.nvim_win_call, win, function() vim.cmd("normal! zz") end)
    end
end

-- mutations ------------------------------------------------------------------

local function open_selected()
    local card = selected()
    if not card then return end
    if not card.url or card.url == "" then
        warn("draft item has no page to open")
        return
    end
    vim.cmd("botright vsplit")
    vim.cmd("Octo " .. card.url)
end

local function set_field(card, field, opt)
    gh_json({
        "project", "item-edit",
        "--project-id", state.project_id,
        "--id", card.id,
        "--field-id", field.id,
        "--single-select-option-id", opt.id,
        "--format", "json",
    }, function(ok, res)
        if not ok then
            err("edit failed: " .. tostring(res))
            return
        end
        card.raw[field.name:lower()] = opt.name
        invalidate()
        follow(card)
        redraw()
    end)
end

-- step the card through the column field's options
local function move_status(dir)
    local card = selected()
    if not card then return end
    local field = cur_view().col_field
    local v, at = card_values(card, field.name)[1], 0
    for i, o in ipairs(field.options) do
        if o.name:lower() == v then at = i end
    end
    local opt = field.options[at + dir]
    if opt then set_field(card, field, opt) end
end

local function edit_field()
    local card = selected()
    if not card then return end
    if #state.select_fields == 0 then
        warn("no single-select fields")
        return
    end
    vim.ui.select(state.select_fields, {
        prompt = "Field:",
        format_item = function(f) return f.name end,
    }, function(field)
        if not field then return end
        vim.ui.select(field.options, {
            prompt = field.name .. ":",
            format_item = function(o) return o.name end,
        }, function(opt)
            if opt then set_field(card, field, opt) end
        end)
    end)
end

-- gh has no reorder command, so drive the GraphQL mutation directly; board only
local function reorder_selected(dir)
    if state.layout ~= "board" then return end
    if #cur_view().sort > 0 then
        warn("view is sorted, positions do not apply")
        return
    end
    local col_v = vcols()[state.cur.col]
    local card = col_v and col_v.cards[state.cur.row]
    if not card then return end
    local target = state.cur.row + dir
    if target < 1 or target > #col_v.cards then return end
    -- afterId: the visible item the card should follow at its new slot (nil = top)
    local after = dir > 0 and col_v.cards[target] or col_v.cards[target - 2]
    local args = {
        "api", "graphql", "-f",
        "query=mutation($p:ID!,$i:ID!,$a:ID){updateProjectV2ItemPosition(input:{projectId:$p,itemId:$i,afterId:$a}){clientMutationId}}",
        "-F", "p=" .. state.project_id,
        "-F", "i=" .. card.id,
    }
    if after then table.insert(args, "-F"); table.insert(args, "a=" .. after.id) end
    gh_json(args, function(ok, res)
        if not ok then
            err("reorder failed: " .. tostring(res))
            return
        end
        local master = state.cards
        for i, k in ipairs(master) do
            if k == card then table.remove(master, i); break end
        end
        local at = 1
        if after then
            for i, k in ipairs(master) do
                if k == after then at = i + 1; break end
            end
        end
        table.insert(master, at, card)
        invalidate()
        state.cur.row = target
        redraw()
    end)
end

local function switch_view(dir)
    local sel = selected()
    state.view_idx = (state.view_idx - 1 + dir) % #state.cviews + 1
    state.layout = cur_view().layout
    invalidate()
    if sel then follow(sel) end
    redraw()
end

local function cycle_layout()
    local sel = selected()
    local i = 1
    for k, l in ipairs(LAYOUT_CYCLE) do
        if l == state.layout then i = k end
    end
    state.layout = LAYOUT_CYCLE[i % #LAYOUT_CYCLE + 1]
    state.rows = nil
    if sel then follow(sel) end
    redraw()
end

local function search()
    vim.ui.input({ prompt = "/" }, function(input)
        input = vim.trim(input or "")
        state.filter = (input ~= "" and input) or nil
        invalidate()
        redraw()
    end)
end

local function nav_vert(d)
    if state.layout == "board" then
        state.cur.row = state.cur.row + d
    else
        state.frow = state.frow + d
    end
    redraw()
end

local function nav_horiz(d)
    if state.layout ~= "board" then return end
    state.cur.col = state.cur.col + d
    redraw()
end

-- project switching ----------------------------------------------------------

local load_board -- forward declaration

local function switch_project(dir)
    if not projects or #projects <= 1 then return end
    local i = proj_idx + dir
    if i < 1 then i = #projects elseif i > #projects then i = 1 end
    load_board(i)
end

local function refresh()
    load_board(proj_idx, true)
end

-- keymaps --------------------------------------------------------------------

local function set_keys(buf)
    local function map(lhs, fn) vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, silent = true }) end
    map("l", function() nav_horiz(1) end)
    map("<Right>", function() nav_horiz(1) end)
    map("h", function() nav_horiz(-1) end)
    map("<Left>", function() nav_horiz(-1) end)
    map("j", function() nav_vert(1) end)
    map("<Down>", function() nav_vert(1) end)
    map("k", function() nav_vert(-1) end)
    map("<Up>", function() nav_vert(-1) end)
    map("L", function() move_status(1) end)
    map("H", function() move_status(-1) end)
    map("<S-Right>", function() move_status(1) end)
    map("<S-Left>", function() move_status(-1) end)
    map("J", function() reorder_selected(1) end)
    map("K", function() reorder_selected(-1) end)
    map("<S-Down>", function() reorder_selected(1) end)
    map("<S-Up>", function() reorder_selected(-1) end)
    map("<Tab>", function() switch_view(1) end)
    map("<S-Tab>", function() switch_view(-1) end)
    map("v", cycle_layout)
    map("p", function() switch_project(1) end)
    map("P", function() switch_project(-1) end)
    map("/", search)
    map("e", edit_field)
    map("<CR>", open_selected)
    map("o", open_selected)
    map("r", refresh)
    map("q", function() vim.api.nvim_buf_delete(buf, { force = true }) end)
    map("<Esc>", function() vim.api.nvim_buf_delete(buf, { force = true }) end)
end

-- model building -------------------------------------------------------------

local function build_cards(items)
    local cards = {}
    for _, it in ipairs(items or {}) do
        local content = it.content or {}
        cards[#cards + 1] = {
            id = it.id,
            title = it.title or content.title or "(untitled)",
            number = content.number,
            url = content.url,
            type = content.type,
            repo_full = content.repository or "",
            repo = (content.repository and content.repository:match("([^/]+)$")) or "",
            raw = it,
        }
    end
    return cards
end

local function build_fields(raw)
    local out = {}
    for _, f in ipairs(raw or {}) do
        local opts = {}
        for _, o in ipairs(f.options or {}) do opts[#opts + 1] = { id = o.id, name = o.name } end
        out[#out + 1] = { id = f.id, name = f.name, type = f.type, options = opts }
    end
    return out
end

local function select_fields(fields)
    local out = {}
    for _, f in ipairs(fields) do
        if f.type == "ProjectV2SingleSelectField" then out[#out + 1] = f end
    end
    return out
end

local VIEW_NODE = "number name layout filter"
    .. " fields(first:50){nodes{... on ProjectV2FieldCommon{name}}}"
    .. " configuration{visibleFields(first:50){nodes{... on ProjectV2FieldCommon{name}}}}"
    .. " groupByFields(first:1){nodes{... on ProjectV2FieldCommon{name}}}"
    .. " verticalGroupByFields(first:1){nodes{... on ProjectV2FieldCommon{name}}}"
    .. " sortByFields(first:5){nodes{direction field{... on ProjectV2FieldCommon{name}}}}"

local function views_args(org, num)
    local project = "projectV2(number:$n){views(first:50){nodes{" .. VIEW_NODE .. "}}}"
    if org == "@me" then
        return { "api", "graphql", "-f", "query=query($n:Int!){viewer{login " .. project .. "}}", "-F", "n=" .. num }
    end
    local q = "query($o:String!,$n:Int!){viewer{login} repositoryOwner(login:$o){... on ProjectV2Owner{" .. project .. "}}}"
    return { "api", "graphql", "-f", "query=" .. q, "-f", "o=" .. org, "-F", "n=" .. num }
end

local function parse_views(data)
    local d = data.data or {}
    local owner = d.repositoryOwner or d.viewer or {}
    local nodes = (((owner.projectV2 or {}).views or {}).nodes) or {}
    local function first_name(conn)
        local n = conn and conn.nodes and conn.nodes[1]
        return n and n.name
    end
    local views = {}
    for _, v in ipairs(nodes) do
        local fields, sort = {}, {}
        -- configuration keeps the view's column order, plain fields come back in project order
        local visible_fields = v.configuration and v.configuration.visibleFields or v.fields or {}
        for _, f in ipairs(visible_fields.nodes or {}) do fields[#fields + 1] = f.name end
        for _, k in ipairs((v.sortByFields or {}).nodes or {}) do
            if k.field and k.field.name then sort[#sort + 1] = { name = k.field.name, desc = k.direction == "DESC" } end
        end
        views[#views + 1] = {
            number = v.number,
            name = v.name,
            layout = v.layout,
            filter = v.filter or "",
            fields = fields,
            group = first_name(v.groupByFields),
            vgroup = first_name(v.verticalGroupByFields),
            sort = sort,
        }
    end
    return views, d.viewer and d.viewer.login
end

-- the gh calls run in parallel, then assemble; renders only if this project is still current
local function fetch(org, num, buf, key, title, idx)
    local got, pending, dead = {}, 4, false
    local function assemble()
        local fields = build_fields(got.fields.fields)
        if not field_by_name(fields, "Status") then err("no Status field on this project"); return end
        local prev = cache[key]
        local views, viewer = {}, nil
        if got.views then
            views, viewer = parse_views(got.views)
        elseif prev then
            views, viewer = prev.views, prev.viewer
        end
        local built = {
            buf = buf,
            org = org,
            num = num,
            title = title,
            idx = idx,
            project_id = got.view.id,
            fields = fields,
            select_fields = select_fields(fields),
            cards = build_cards(got.items.items),
            views = views,
            viewer = viewer,
            cur = (prev and prev.cur) or { col = 1, row = 1 },
            frow = (prev and prev.frow) or 1,
            view_idx = (prev and prev.view_idx) or 1,
            layout = prev and prev.layout,
            filter = prev and prev.filter,
            ts = os.time(),
        }
        prepare(built)
        cache[key] = built
        disk_write(key, {
            v = CACHE_VERSION, org = org, num = num, title = title, project_id = built.project_id,
            fields = fields, cards = built.cards, views = views, viewer = viewer, ts = built.ts,
        })
        if proj_idx ~= idx or not vim.api.nvim_buf_is_valid(buf) then return end
        state = built
        set_keys(buf)
        redraw()
    end
    local function one(name, args, optional)
        gh_json(args, function(ok, data)
            if dead then return end
            if not ok and not optional then dead = true; err(tostring(data)); return end
            if not ok then
                if not views_warned[key] then warn("saved views unavailable: " .. tostring(data)) end
                views_warned[key] = true
                data = nil
            end
            got[name] = data
            pending = pending - 1
            if pending == 0 then assemble() end
        end)
    end
    one("view", { "project", "view", num, "--owner", org, "--format", "json" })
    one("fields", { "project", "field-list", num, "--owner", org, "--format", "json", "-L", "50" })
    one("items", { "project", "item-list", num, "--owner", org, "--format", "json", "-L", ITEM_LIMIT })
    one("views", views_args(org, num), true)
end

-- render the project at `idx` from memory, then disk, then a background refresh unless the cache is fresh
load_board = function(idx, force)
    proj_idx = idx
    local p = projects[idx]
    local num = tostring(p.number)
    local title = p.title or ("Project " .. num)
    local key = cur_org .. "/" .. num
    pcall(vim.api.nvim_buf_set_name, board_buf, "ghproject://" .. cur_org .. "/" .. num)

    local cached = cache[key]
    if not cached then
        local d = disk_read(key)
        if d and d.v == CACHE_VERSION then
            d.cur, d.frow, d.view_idx, d.views = { col = 1, row = 1 }, 1, 1, d.views or {}
            d.select_fields = select_fields(d.fields)
            prepare(d)
            cache[key] = d; cached = d
        end
    end
    if cached then
        cached.buf = board_buf
        cached.title = title
        cached.idx = idx
        state = cached
        set_keys(board_buf)
        redraw()
    else
        vim.bo[board_buf].modifiable = true
        vim.api.nvim_buf_set_lines(board_buf, 0, -1, false, { "", "  loading " .. title .. " ..." })
        vim.bo[board_buf].modifiable = false
    end
    if not force and cached and cached.ts and (os.time() - cached.ts) < TTL then return end
    fetch(cur_org, num, board_buf, key, title, idx)
end

-- set proj_idx to the default project's position (prepending it if absent), then cb()
local function pick_project_index(default_num, cb)
    local idx
    for i, p in ipairs(projects) do
        if tostring(p.number) == tostring(default_num) then idx = i; break end
    end
    if not idx then
        table.insert(projects, 1, { number = default_num, title = "Project " .. default_num })
        idx = 1
    end
    proj_idx = idx
    cb()
end

-- fetch the org's project list once (disk cache serves it offline), pick the default, then cb()
local function ensure_projects(default_num, cb)
    if projects and projects_org == cur_org then cb(); return end
    local pkey = "projects/" .. cur_org
    local disk = disk_read(pkey)
    if disk and disk.projects and disk.ts and (os.time() - disk.ts) < TTL then
        projects, projects_org = disk.projects, cur_org
        return pick_project_index(default_num, cb)
    end
    gh_json({ "project", "list", "--owner", cur_org, "--format", "json" }, function(ok, data)
        if ok and data.projects and #data.projects > 0 then
            projects = {}
            for _, p in ipairs(data.projects) do projects[#projects + 1] = { number = p.number, title = p.title } end
            disk_write(pkey, { projects = projects, ts = os.time() })
        elseif disk and disk.projects then
            projects = disk.projects -- gh failed (rate limit/offline): fall back to the cache
        else
            projects = { { number = default_num, title = "Project " .. default_num } }
        end
        projects_org = cur_org
        pick_project_index(default_num, cb)
    end)
end

function M.open_board()
    -- org optional: unset uses the personal account (@me); project number required
    local org = (vim.env.OCTO_DEFAULT_ORG and vim.env.OCTO_DEFAULT_ORG ~= "" and vim.env.OCTO_DEFAULT_ORG) or "@me"
    local num = vim.env.OCTO_DEFAULT_PROJECT
    if not num or num == "" then
        warn("set OCTO_DEFAULT_PROJECT in .identity/env")
        return
    end
    if vim.fn.executable("gh") == 0 then
        err("gh not found")
        return
    end
    cur_org = org

    local fresh = not (board_buf and vim.api.nvim_buf_is_valid(board_buf))
    if fresh then
        board_buf = vim.api.nvim_create_buf(true, true)
        vim.bo[board_buf].buftype = "nofile"
        vim.bo[board_buf].bufhidden = "hide" -- hide, not wipe: an opened card must leave the board reachable
    end
    vim.api.nvim_win_set_buf(0, board_buf)
    if fresh then
        pcall(vim.api.nvim_buf_set_name, board_buf, "ghproject://board")
        vim.bo[board_buf].filetype = "ghproject" -- set once in the window, so ftplugin window options land there
    end

    ensure_projects(num, function() load_board(proj_idx) end)
end

function M.setup()
    vim.keymap.set("n", "<leader>gp", M.open_board, { desc = "GitHub project board" })
end

return M
