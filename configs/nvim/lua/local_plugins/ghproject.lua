-- GitHub Projects V2 kanban board. Org + project number from the environment
-- (OCTO_DEFAULT_ORG, OCTO_DEFAULT_PROJECT), so no work identifiers live in the repo.
-- Views: board (kanban), table, list. Tab switches project, / filters, e edits fields.
-- Future: item create/archive/delete are not implemented yet.
local M = {}

local COL_WIDTH = 30          -- board column display width
local LIST_WIDTH = 70         -- list-view title truncation
local LEFT = "  "             -- left margin on grid lines
local SEP = " │ "             -- between board columns
local GAP = "  "              -- between table columns
local NO_STATUS = "(No status)"
local NS = vim.api.nvim_create_namespace("ghproject")
local LEGEND =
    "hjkl move · H/L status · J/K reorder · v view · / filter · e edit · ⏎ open · ⇥ project · r refresh · q quit"

-- module state
local state = nil        -- current board: { buf, org, num, title, idx, project_id, field_id,
                         --                  select_fields, columns, cur, frow, view, filter }
local cache = {}         -- ["org/num"] = state, so reopening renders before the refresh lands
local projects = nil     -- [{number, title}] for the org, fetched once
local projects_org = nil -- the org `projects` was fetched for
local proj_idx = 1       -- current index into `projects`
local cur_org = nil      -- org of the open board
local board_buf = nil    -- the reusable board buffer

-- persistent cache: survives restarts and avoids refetching (and gh rate limits)
local CACHE_DIR = vim.fn.stdpath("cache") .. "/ghproject"
local TTL = 300 -- seconds; a cache younger than this skips the background refresh

local function cache_path(key) return CACHE_DIR .. "/" .. key:gsub("[^%w]", "_") .. ".json" end

local function disk_read(key)
    local f = io.open(cache_path(key), "r")
    if not f then return nil end
    local raw = f:read("*a"); f:close()
    local ok, d = pcall(vim.json.decode, raw)
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
            local ok, decoded = pcall(vim.json.decode, res.stdout)
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

-- client-side filter over already-fetched cards ------------------------------

local function match_card(card, q)
    return ((card.title or ""):lower():find(q, 1, true) ~= nil)
        or (("#" .. tostring(card.number or "")):lower():find(q, 1, true) ~= nil)
        or ((card.repo or ""):lower():find(q, 1, true) ~= nil)
end

-- the columns as the current filter shows them (same order/count, fewer cards)
local function vcols()
    if not state.filter or state.filter == "" then return state.columns end
    local q = state.filter:lower()
    local out = {}
    for i, c in ipairs(state.columns) do
        local cards = {}
        for _, card in ipairs(c.cards) do
            if match_card(card, q) then cards[#cards + 1] = card end
        end
        out[i] = { name = c.name, opt_id = c.opt_id, cards = cards }
    end
    return out
end

-- every visible card, grouped by column order (used by table + list)
local function flat_visible()
    local out = {}
    for _, c in ipairs(vcols()) do
        for _, card in ipairs(c.cards) do out[#out + 1] = card end
    end
    return out
end

local function visible_count()
    local n = 0
    for _, c in ipairs(vcols()) do n = n + #c.cards end
    return n
end

-- selection helpers ----------------------------------------------------------

local function selected()
    if state.view == "board" then
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

local function master_col_of(card)
    for i, c in ipairs(state.columns) do
        for _, k in ipairs(c.cards) do
            if k == card then return i end
        end
    end
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

local TABLE_COLS = {
    { name = "#", w = 7, get = function(c) return "#" .. (c.number or "-") end },
    { name = "Title", w = 46, get = function(c) return c.title end },
    { name = "Status", w = 17, get = function(c) return c.status or "" end },
    { name = "Priority", w = 9, get = function(c) return c.raw and c.raw.priority or "" end },
    { name = "Size", w = 6, get = function(c) return c.raw and c.raw.size or "" end },
    { name = "Repo", w = 22, get = function(c) return c.repo or "" end },
}

local function render_header(lines, marks)
    local views = { board = "Board", table = "Table", list = "List" }
    local n = projects and #projects or 1
    local h = string.format("  %s  [%d/%d]  · %s", state.title or "", state.idx, n, views[state.view])
    if state.filter then h = h .. string.format("  · filter: %s (%d)", state.filter, visible_count()) end
    lines[#lines + 1] = h
    lines[#lines + 1] = "  " .. LEGEND
    marks[#marks + 1] = { grp("GhProjectTitle", "Title"), 0, 0, -1 }
    marks[#marks + 1] = { grp("GhProjectHint", "Comment"), 1, 0, -1 }
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
    local items = flat_visible()
    local hcells = {}
    for i, tc in ipairs(TABLE_COLS) do hcells[i] = pad(tc.name, tc.w) end
    lines[#lines + 1] = LEFT .. table.concat(hcells, GAP)
    local hln, hr = #lines - 1, ranges(hcells, #LEFT, #GAP)
    for i = 1, #TABLE_COLS do marks[#marks + 1] = { header_group(i), hln, hr[i][1], hr[i][2] } end

    local total = (#TABLE_COLS - 1) * vim.fn.strdisplaywidth(GAP)
    for _, tc in ipairs(TABLE_COLS) do total = total + tc.w end
    lines[#lines + 1] = LEFT .. string.rep("─", total)
    marks[#marks + 1] = { grp("GhProjectSep", "Comment"), #lines - 1, 0, -1 }

    local first = #lines
    for i, card in ipairs(items) do
        local cells = {}
        for j, tc in ipairs(TABLE_COLS) do cells[j] = pad(tc.get(card), tc.w) end
        lines[#lines + 1] = LEFT .. table.concat(cells, GAP)
        if i == state.frow then marks[#marks + 1] = { grp("GhProjectSel", "Visual"), #lines - 1, 0, -1 } end
    end
    if items[state.frow] then return { first + state.frow, #LEFT } end
end

local function render_list(lines, marks)
    local idx, cursor, first = 0, nil, true
    for ci, col in ipairs(vcols()) do
        if #col.cards > 0 then
            if not first then lines[#lines + 1] = "" end
            first = false
            lines[#lines + 1] = string.format("  %s  (%d)", col.name, #col.cards)
            marks[#marks + 1] = { header_group(ci), #lines - 1, 0, -1 }
            for _, card in ipairs(col.cards) do
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
    if s.view == "table" then
        cursor = render_table(lines, marks)
    elseif s.view == "list" then
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

-- set the Status of a card to a target option, re-bucketing the model in place
local function apply_status(card, opt_id, cb)
    gh_json({
        "project", "item-edit",
        "--project-id", state.project_id,
        "--id", card.id,
        "--field-id", state.field_id,
        "--single-select-option-id", opt_id,
        "--format", "json",
    }, function(ok, res)
        if not ok then
            err("move failed: " .. tostring(res))
            return
        end
        local from = master_col_of(card)
        local target
        for _, c in ipairs(state.columns) do
            if c.opt_id == opt_id then target = c end
        end
        if from and target then
            for i, k in ipairs(state.columns[from].cards) do
                if k == card then table.remove(state.columns[from].cards, i); break end
            end
            card.status = target.name
            if card.raw then card.raw.status = target.name end
            target.cards[#target.cards + 1] = card
        end
        state.cur.col, state.cur.row = board_pos(card)
        state.frow = flat_index(card)
        redraw()
        if cb then cb() end
    end)
end

local function move_status(dir)
    local card = selected()
    if not card then return end
    local ci = master_col_of(card)
    if not ci then return end
    local ti = ci + dir
    if ti < 1 or ti > #state.columns then return end
    local opt = state.columns[ti].opt_id
    if not opt then
        warn("cannot move into " .. NO_STATUS)
        return
    end
    apply_status(card, opt)
end

-- pick any single-select field and option, then set it on the selected card
local function edit_field()
    local card = selected()
    if not card then return end
    if not state.select_fields or #state.select_fields == 0 then
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
            if not opt then return end
            if field.id == state.field_id then
                apply_status(card, opt.id)
                return
            end
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
                card.raw = card.raw or {}
                card.raw[field.name:lower()] = opt.name
                redraw()
            end)
        end)
    end)
end

-- reorder the selected card within its column (Projects V2 item position).
-- gh has no reorder command, so drive the GraphQL mutation directly. Board only.
local function reorder_selected(dir)
    if state.view ~= "board" then return end
    local vc = vcols()
    local col_v = vc[state.cur.col]
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
        local master = state.columns[state.cur.col].cards
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
        state.cur.row = target
        redraw()
    end)
end

local function cycle_view()
    local sel = selected()
    local next_view = { board = "table", table = "list", list = "board" }
    state.view = next_view[state.view]
    if sel then
        state.cur.col, state.cur.row = board_pos(sel)
        state.frow = flat_index(sel)
    end
    redraw()
end

local function search()
    vim.ui.input({ prompt = "/" }, function(input)
        if input == nil then input = "" end
        input = vim.trim(input)
        state.filter = (input ~= "" and input) or nil
        redraw()
    end)
end

local function nav_vert(d)
    if state.view == "board" then
        state.cur.row = state.cur.row + d
    else
        state.frow = state.frow + d
    end
    redraw()
end

local function nav_horiz(d)
    if state.view ~= "board" then return end
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
    map("<Tab>", function() switch_project(1) end)
    map("<S-Tab>", function() switch_project(-1) end)
    map("v", cycle_view)
    map("/", search)
    map("e", edit_field)
    map("<CR>", open_selected)
    map("o", open_selected)
    map("r", refresh)
    map("q", function() vim.api.nvim_buf_delete(buf, { force = true }) end)
    map("<Esc>", function() vim.api.nvim_buf_delete(buf, { force = true }) end)
end

-- model building -------------------------------------------------------------

-- build the column model from field options (order) + items (grouped by status)
local function build_columns(status_field, items)
    local columns = { { name = NO_STATUS, opt_id = nil, cards = {} } }
    local by_name = { [NO_STATUS] = columns[1] }
    for _, opt in ipairs(status_field.options or {}) do
        local col = { name = opt.name, opt_id = opt.id, cards = {} }
        columns[#columns + 1] = col
        by_name[opt.name] = col
    end
    for _, it in ipairs(items or {}) do
        local content = it.content or {}
        local col = by_name[it.status or ""] or columns[1]
        col.cards[#col.cards + 1] = {
            id = it.id,
            title = it.title or content.title or "(untitled)",
            number = content.number,
            url = content.url,
            status = it.status or "",
            repo = (content.repository and content.repository:match("([^/]+)$")) or "",
            raw = it, -- table view reads other single-select fields straight off this
        }
    end
    -- drop the No-status column when empty, so it never shows as a stray column
    if #columns[1].cards == 0 then table.remove(columns, 1) end
    return columns
end

-- all single-select fields, in field-list order, for the `e` picker (Status included)
local function select_fields(fields)
    local out = {}
    for _, f in ipairs(fields or {}) do
        if f.type == "ProjectV2SingleSelectField" then
            local opts = {}
            for _, o in ipairs(f.options or {}) do opts[#opts + 1] = { id = o.id, name = o.name } end
            out[#out + 1] = { id = f.id, name = f.name, options = opts }
        end
    end
    return out
end

-- the three gh calls run in parallel (one round trip, not three), then assemble.
-- Only render if this project is still the current one (guards fast switches).
local function fetch(org, num, buf, key, title, idx)
    local got, pending, dead = {}, 3, false
    local function one(name, args)
        gh_json(args, function(ok, data)
            if dead then return end
            if not ok then dead = true; err(tostring(data)); return end
            got[name] = data
            pending = pending - 1
            if pending > 0 then return end
            local status_field
            for _, f in ipairs(got.fields.fields or {}) do
                if f.name == "Status" then status_field = f end
            end
            if not status_field then err("no Status field on this project"); return end
            local prev = cache[key]
            local built = {
                buf = buf,
                org = org,
                num = num,
                title = title,
                idx = idx,
                project_id = got.view.id,
                field_id = status_field.id,
                select_fields = select_fields(got.fields.fields),
                columns = build_columns(status_field, got.items.items),
                cur = (prev and prev.cur) or { col = 1, row = 1 },
                frow = (prev and prev.frow) or 1,
                view = (prev and prev.view) or "board",
                filter = prev and prev.filter or nil,
            }
            built.ts = os.time()
            cache[key] = built
            -- persist the durable board (no buffer handle) for next session
            disk_write(key, {
                org = org, num = num, title = title,
                project_id = built.project_id, field_id = built.field_id,
                select_fields = built.select_fields, columns = built.columns, ts = built.ts,
            })
            if proj_idx ~= idx or not vim.api.nvim_buf_is_valid(buf) then return end
            state = built
            set_keys(buf)
            redraw()
        end)
    end
    one("view", { "project", "view", num, "--owner", org, "--format", "json" })
    one("fields", { "project", "field-list", num, "--owner", org, "--format", "json", "-L", "50" })
    one("items", { "project", "item-list", num, "--owner", org, "--format", "json", "-L", "200" })
end

-- render the project at `idx` (memory, then disk, then a background refresh).
-- force=true always refetches; otherwise a cache younger than TTL skips the network.
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
        if d then
            d.cur = { col = 1, row = 1 }; d.frow = 1; d.view = "board"
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
    -- skip the refetch when the cache is fresh, unless forced
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

-- fetch the org's project list once, pick the default's index, then run cb().
-- disk cache serves it offline; a fresh cache skips the gh call entirely.
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
        -- hide, not wipe: opening a card must leave the board reachable via <C-o>/:b
        vim.bo[board_buf].bufhidden = "hide"
    end
    vim.api.nvim_win_set_buf(0, board_buf)
    if fresh then
        pcall(vim.api.nvim_buf_set_name, board_buf, "ghproject://board")
        -- set filetype once the buffer is in the window, so the ftplugin's window
        -- options land on the right window
        vim.bo[board_buf].filetype = "ghproject"
    end

    ensure_projects(num, function() load_board(proj_idx) end)
end

function M.setup()
    vim.keymap.set("n", "<leader>gp", M.open_board, { desc = "GitHub project board" })
end

return M
