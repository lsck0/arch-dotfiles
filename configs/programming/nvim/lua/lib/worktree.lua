-- Git worktrees of the current repo: switch the tab to one, or add one next to the existing ones.
--
-- `:G worktree add <path>` resolves <path> against the current worktree, which nested new worktrees inside it
-- (~/projects/probe/master/uwu), and git-worktree.nvim put them inside `.bare/`. `add` follows the layout instead:
--   <repo>/.bare + <repo>/branches/<slug>   bare layout of clones-sdd-repos.sh
--   <bare>/<slug>                            worktrees inside a plain bare repo (~/projects/probe)
--   ~/.worktrees/<repo>/<slug>               normal checkout, as configs/base/git/wtree.sh does
-- Once linked worktrees exist, the dir most of them share wins over all of the above.
local M = {}

local WORKTREE_HOME = vim.fs.normalize("~/.worktrees")

---@param args string[]
---@return string? stdout nil when git failed
---@return string stderr
local function git(args)
    local cmd = vim.list_extend({ "git" }, args)
    local res = vim.system(cmd, { text = true, cwd = require("lib.root").git() }):wait()
    return res.code == 0 and res.stdout or nil, res.stderr or ""
end

--- `git worktree list --porcelain`; the first entry is the main checkout or the bare repo itself.
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
        -- ties go to the shallower dir, so one stray nested worktree never becomes the convention
        if not best or count[parent] > count[best] or (count[parent] == count[best] and #parent < #best) then
            best = parent
        end
    end
    if best then return vim.fs.joinpath(best, slug) end

    local main = list[1].path
    if not list[1].bare then return vim.fs.joinpath(WORKTREE_HOME, vim.fs.basename(main), slug) end
    if vim.fs.basename(main) == ".bare" then return vim.fs.joinpath(vim.fs.dirname(main), "branches", slug) end
    return vim.fs.joinpath(main, slug)
end

--- Switch the tab to BRANCH's worktree, creating the worktree (and the branch, tracking origin if it has one) first.
---@param branch string
function M.add(branch)
    local list = worktrees()
    if not list then return end
    for _, tree in ipairs(list) do
        if tree.branch == branch then return require("lib.projects").open(tree.path) end
    end

    -- slashes flattened like clones-sdd-repos.sh's slug_of, so feat/x is one dir, not two
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

--- Pick a local or origin branch for `M.add`; a name that matches nothing creates that branch.
function M.pick_branch()
    local out = git({ "for-each-ref", "--format=%(refname)", "refs/heads", "refs/remotes/origin" })
    if not out then return vim.notify("worktree: not a git repo", vim.log.levels.ERROR) end
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
        if branch ~= "" then M.add(branch) end
    end)
end

--- Pick one of the repo's worktrees and switch the tab to it.
function M.pick()
    local list = worktrees()
    if not list then return end
    local items = {}
    for _, tree in ipairs(list) do
        if not tree.bare then
            local display = (tree.branch or "detached") .. "  " .. vim.fn.fnamemodify(tree.path, ":~")
            table.insert(items, { display = display, value = tree.path })
        end
    end
    require("lib.pick").telescope("Worktrees", items, function(path)
        if path then require("lib.projects").open(path) end
    end)
end

return M
