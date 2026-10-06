-- Git checkouts and worktrees under the tms search dirs, the dirs `hms` and tms's popup show plus bare-repo worktrees.
-- project.nvim only listed directories this nvim had already visited, so a repo was missing from the picker
-- until it had been opened some other way.
local M = {}

local DEFAULT_DIRS = { { path = vim.fs.normalize("~/projects"), depth = 10 } }

-- vendored repos are not projects; mirrors the --exclude list in scripts/hms.sh
local EXCLUDE = { "elpa", "node_modules", ".cargo", "vendor", "target" }

--- Parse `~/.config/tms/config.toml` so the picker and `hms` never disagree about what a project is.
---@return { path: string, depth: integer }[]
local function search_dirs()
    local file = vim.fs.normalize("~/.config/tms/config.toml")
    local fd = io.open(file, "r")
    if not fd then return DEFAULT_DIRS end

    local dirs, current = {}, nil
    for line in fd:lines() do
        if line:match("^%s*%[%[search_dirs%]%]") then
            current = { depth = 10 }
            table.insert(dirs, current)
        elseif current then
            local path = line:match('^%s*path%s*=%s*"(.-)"')
            local depth = line:match("^%s*depth%s*=%s*(%d+)")
            if path then current.path = vim.fs.normalize(path) end
            if depth then current.depth = tonumber(depth) end
        end
    end
    fd:close()

    dirs = vim.tbl_filter(function(d) return d.path ~= nil end, dirs)
    return #dirs > 0 and dirs or DEFAULT_DIRS
end

--- A `.git` dir marks a checkout. A `.git` file marks a worktree only when it points into `<gitdir>/worktrees/`:
--- that is how bare-repo layouts (`<repo>/.bare` + `<repo>/branches/<branch>`, or worktrees inside a plain bare
--- repo) show up, while submodules and the bare layout's own root (`gitdir: ./.bare`) are not projects.
---@param path string
---@return boolean
local function is_checkout(path)
    if vim.fn.isdirectory(path) == 1 then return true end
    local fd = io.open(path, "r")
    if not fd then return false end
    local line = fd:read("*l") or ""
    fd:close()
    return line:match("^gitdir: .*/worktrees/[^/]+/?$") ~= nil
end

--- Every git checkout and worktree under the search dirs, sorted by display path.
---@return { display: string, path: string }[]
function M.list()
    if vim.fn.executable("fd") ~= 1 then
        vim.notify("projects: fd is not installed", vim.log.levels.ERROR)
        return {}
    end

    local seen, out = {}, {}
    for _, dir in ipairs(search_dirs()) do
        if vim.fn.isdirectory(dir.path) == 1 then
            local cmd = { "fd", "--type", "d", "--type", "f", "--hidden", "--no-ignore" }
            vim.list_extend(cmd, { "--max-depth", tostring(dir.depth) })
            for _, ex in ipairs(EXCLUDE) do
                vim.list_extend(cmd, { "--exclude", ex })
            end
            vim.list_extend(cmd, { "^\\.git$", dir.path })

            local res = vim.system(cmd, { text = true }):wait()
            for line in (res.stdout or ""):gmatch("[^\r\n]+") do
                -- normalize first: fd prints directories with a trailing slash, which dirname would keep
                local git = vim.fs.normalize(line)
                local path = vim.fs.dirname(git)
                if not seen[path] and is_checkout(git) then
                    seen[path] = true
                    -- display relative to its search dir, as tms and hms show it
                    local display = path:sub(1, #dir.path) == dir.path and path:sub(#dir.path + 2) or path
                    table.insert(out, { display = display, path = path })
                end
            end
        end
    end

    table.sort(out, function(a, b) return a.display < b.display end)
    return out
end

--- tcd into DIR and re-root the explorer there, so the whole tab moves to the project.
---@param dir string
function M.open(dir)
    pcall(vim.cmd.tcd, vim.fn.fnameescape(dir))
    local explorer = require("snacks.picker").get({ source = "explorer" })[1]
    if explorer and not explorer.closed then
        explorer:set_cwd(dir)
        explorer:find()
    end
    require("telescope.builtin").find_files({ cwd = dir })
end

--- Telescope picker over `M.list()`; confirming switches the tab to that project.
function M.pick()
    local items = {}
    for _, item in ipairs(M.list()) do
        table.insert(items, { display = item.display, value = item.path })
    end
    if #items == 0 then
        vim.notify("projects: no git repos under the tms search dirs", vim.log.levels.WARN)
        return
    end
    require("lib.pick").telescope("Projects", items, function(path)
        if path then M.open(path) end
    end)
end

return M
