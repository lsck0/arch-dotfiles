local M = {}

local DEFAULT_DIRS = { { path = vim.fs.normalize("~/projects"), depth = 10 } }

-- vendored repos are not projects; mirrors FD_EXCLUDES in scripts/hms.nu
local EXCLUDE = { "elpa", "node_modules", ".cargo", "vendor", "target" }

---@return { path: string, depth: integer }[] dirs, string[] bookmarks
local function tms_config()
    local config_home = vim.env.XDG_CONFIG_HOME or (vim.env.HOME .. "/.config")
    local file = vim.fs.normalize(config_home .. "/tms/config.toml")
    local fd = io.open(file, "r")
    if not fd then
        return DEFAULT_DIRS, {}
    end

    local dirs, bookmarks, current, in_bookmarks = {}, {}, nil, false
    for line in fd:lines() do
        if line:match("^%s*%[%[search_dirs%]%]") then
            current, in_bookmarks = { depth = 10 }, false
            table.insert(dirs, current)
        elseif line:match("^%s*bookmarks%s*=") then
            current, in_bookmarks = nil, true
        end
        if in_bookmarks then
            for path in line:gmatch('"(.-)"') do
                table.insert(bookmarks, vim.fs.normalize(path))
            end
            in_bookmarks = not line:find("]", 1, true)
        elseif current then
            local path = line:match('^%s*path%s*=%s*"(.-)"')
            local depth = line:match("^%s*depth%s*=%s*(%d+)")
            if path then
                current.path = vim.fs.normalize(path)
            end
            if depth then
                current.depth = tonumber(depth)
            end
        end
    end
    fd:close()

    dirs = vim.tbl_filter(function(d)
        return d.path ~= nil
    end, dirs)
    return #dirs > 0 and dirs or DEFAULT_DIRS, bookmarks
end

---@param path string
---@return boolean
local function is_checkout(path)
    if vim.fn.isdirectory(path) == 1 then
        return true
    end
    local fd = io.open(path, "r")
    if not fd then
        return false
    end
    local line = fd:read("*l") or ""
    fd:close()
    return line:match("^gitdir: .*/worktrees/[^/]+/?$") ~= nil
end

---@param head string
---@return boolean
local function is_bare(head)
    local dir = vim.fs.dirname(head)
    if head:find("/%.git/") or head:find("/%.bare/") then
        return false
    end
    return vim.fn.isdirectory(dir .. "/objects") == 1 and vim.fn.isdirectory(dir .. "/refs") == 1
end

---@return { display: string, path: string }[]
function M.list()
    if vim.fn.executable("fd") ~= 1 then
        vim.notify("projects: fd is not installed", vim.log.levels.ERROR)
        return {}
    end

    local dirs, bookmarks = tms_config()
    local seen, out = {}, {}
    local function add(path, display)
        if not seen[path] then
            seen[path] = true
            table.insert(out, { display = display, path = path })
        end
    end
    for _, dir in ipairs(dirs) do
        if vim.fn.isdirectory(dir.path) == 1 then
            local cmd = { "fd", "--type", "d", "--type", "f", "--hidden", "--no-ignore", "--prune" }
            vim.list_extend(cmd, { "--max-depth", tostring(dir.depth + 1) })
            for _, ex in ipairs(EXCLUDE) do
                vim.list_extend(cmd, { "--exclude", ex })
            end
            vim.list_extend(cmd, { "^(\\.git|HEAD)$", dir.path })

            local res = vim.system(cmd, { text = true }):wait()
            for line in (res.stdout or ""):gmatch("[^\r\n]+") do
                -- fd prints dirs with a trailing slash, which dirname would keep
                local entry = vim.fs.normalize(line)
                local path = vim.fs.dirname(entry)
                local project
                if vim.fs.basename(entry) == "HEAD" then
                    project = is_bare(entry)
                else
                    project = is_checkout(entry)
                end
                if project then
                    local display = path:sub(1, #dir.path) == dir.path and path:sub(#dir.path + 2) or path
                    add(path, display)
                end
            end
        end
    end
    for _, path in ipairs(bookmarks) do
        if vim.fn.isdirectory(path) == 1 then
            add(path, vim.fs.basename(path))
        end
    end

    table.sort(out, function(a, b)
        return a.display < b.display
    end)
    return out
end

---@param dir string
function M.open(dir)
    pcall(vim.cmd.tcd, vim.fn.fnameescape(dir))
    vim.cmd.enew()
    require("lib.explorer").open(dir)
end

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
        if path then
            M.open(path)
        end
    end)
end

return M
