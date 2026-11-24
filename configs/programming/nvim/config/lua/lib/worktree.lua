-- `:G worktree add` that follows the repo's worktree layout (as wtree.nu).

local M = {}

local WORKTREE_HOME = vim.fs.normalize("~/.worktrees")

local function git_root()
    local name = vim.api.nvim_buf_get_name(0)
    local start = name ~= "" and name or vim.uv.cwd()
    return vim.fs.root(start, ".git") or vim.uv.cwd()
end

---@param args string[]
---@return string? stdout nil when git failed
---@return string stderr
local function git(args)
    local cmd = vim.list_extend({ "git" }, args)
    local res = vim.system(cmd, { text = true, cwd = git_root() }):wait()
    return res.code == 0 and res.stdout or nil, res.stderr or ""
end

---@return { path: string, branch: string?, bare: boolean }[]?
local function worktrees()
    local out, err = git({ "worktree", "list", "--porcelain" })
    if not out then
        vim.notify("worktree: " .. vim.trim(err), vim.log.levels.ERROR)
        return nil
    end
    local list = {}
    for line in out:gmatch("[^\n]+") do
        local path = line:match("^worktree (.+)$")
        if path then
            table.insert(list, { path = path, bare = false })
        elseif line == "bare" then
            list[#list].bare = true
        elseif line:match("^branch refs/heads/") then
            list[#list].branch = line:match("^branch refs/heads/(.+)$")
        end
    end
    return list
end

---@param list { path: string, bare: boolean }[]
---@param slug string
---@return string
local function dir_for(list, slug)
    local count, best = {}, nil
    for i = 2, #list do
        local parent = vim.fs.dirname(list[i].path)
        count[parent] = (count[parent] or 0) + 1
        if not best or count[parent] > count[best] or (count[parent] == count[best] and #parent < #best) then
            best = parent
        end
    end
    if best then
        return vim.fs.joinpath(best, slug)
    end

    local main = list[1].path
    if not list[1].bare then
        return vim.fs.joinpath(WORKTREE_HOME, vim.fs.basename(main), slug)
    end
    if vim.fs.basename(main) == ".bare" then
        return vim.fs.joinpath(vim.fs.dirname(main), "branches", slug)
    end
    return vim.fs.joinpath(main, slug)
end

---@param branch string
function M.add(branch)
    local list = worktrees()
    if not list then
        return
    end
    for _, tree in ipairs(list) do
        if tree.branch == branch then
            return require("lib.projects").open(tree.path)
        end
    end

    local dir = dir_for(list, (branch:gsub("/", "-")))
    local args = { "worktree", "add", "-b", branch, dir }
    if git({ "show-ref", "--verify", "--quiet", "refs/heads/" .. branch }) then
        args = { "worktree", "add", dir, branch }
    elseif git({ "show-ref", "--verify", "--quiet", "refs/remotes/origin/" .. branch }) then
        args = { "worktree", "add", "--track", "-b", branch, dir, "origin/" .. branch }
    end
    local out, err = git(args)
    if not out then
        vim.notify("worktree: " .. vim.trim(err), vim.log.levels.ERROR)
        return
    end
    vim.notify("worktree: " .. vim.fn.fnamemodify(dir, ":~"))
    require("lib.projects").open(dir)
end

function M.pick_branch()
    local out = git({ "for-each-ref", "--format=%(refname)", "refs/heads", "refs/remotes/origin" })
    if not out then
        return vim.notify("worktree: not a git repo", vim.log.levels.ERROR)
    end
    local seen, items = {}, {}
    for ref in out:gmatch("[^\n]+") do
        local branch = ref:match("^refs/heads/(.+)$") or ref:match("^refs/remotes/origin/(.+)$")
        if branch and branch ~= "HEAD" and not seen[branch] then
            seen[branch] = true
            table.insert(items, { display = branch, value = branch })
        end
    end
    require("lib.pick").telescope("Worktree branch (new name creates it)", items, function(branch, query)
        branch = branch or vim.trim(query)
        if branch ~= "" then
            M.add(branch)
        end
    end)
end

function M.pick()
    local list = worktrees()
    if not list then
        return
    end
    local items = {}
    for _, tree in ipairs(list) do
        if not tree.bare then
            local display = (tree.branch or "detached") .. "  " .. vim.fn.fnamemodify(tree.path, ":~")
            table.insert(items, { display = display, value = tree.path })
        end
    end
    require("lib.pick").telescope("Worktrees", items, function(path)
        if path then
            require("lib.projects").open(path)
        end
    end)
end

return M
