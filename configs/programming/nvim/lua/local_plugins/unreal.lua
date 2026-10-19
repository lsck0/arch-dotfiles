local M = {}

local done = {}

local function is_uproject(name)
    return name:match("%.uproject$") ~= nil
end

local function uproject(path)
    return vim.fs.find(is_uproject, { path = path, upward = true, limit = 1 })[1]
end

local function project_root(path)
    local file = uproject(path)
    return file and vim.fs.dirname(file)
end

local function engine_root()
    local data = vim.env.XDG_DATA_HOME or (vim.env.HOME .. "/.local/share")
    -- no nil slot: an unset $UE_ROOT first would end ipairs before it looks at any dir
    local dirs = { data .. "/unreal-engine", "/opt/unreal-engine" }
    if vim.env.UE_ROOT then
        table.insert(dirs, 1, vim.env.UE_ROOT)
    end
    for _, dir in ipairs(dirs) do
        if vim.uv.fs_stat(dir .. "/Engine/Build/BatchFiles/Linux/Build.sh") then
            return dir
        end
    end
end

local function editor_target(root)
    local target = vim.fs.find(function(name)
        return name:match("Editor%.Target%.cs$") ~= nil
    end, { path = root .. "/Source", limit = 1 })[1]
    if target then
        return vim.fs.basename(target):gsub("%.Target%.cs$", "")
    end
    return vim.fs.basename(uproject(root)):gsub("%.uproject$", "") .. "Editor"
end

local function mtime(path)
    local stat = vim.uv.fs_stat(path)
    return stat and stat.mtime.sec or 0
end

local function stale(root)
    local db = mtime(root .. "/compile_commands.json")
    if db == 0 then
        return true
    end
    local inputs = vim.fs.find(function(name)
        return name:match("%.Build%.cs$") or name:match("%.Target%.cs$") or name:match("%.uproject$")
    end, { path = root, limit = math.huge, type = "file" })
    for _, file in ipairs(inputs) do
        if not file:find("/Intermediate/", 1, true) and not file:find("/Saved/", 1, true) and mtime(file) > db then
            return true
        end
    end
    return false
end

local function git_exclude(root)
    local res = vim.system({ "git", "-C", root, "rev-parse", "--git-path", "info/exclude" }, { text = true }):wait()
    if res.code ~= 0 then
        return
    end
    local exclude = vim.trim(res.stdout)
    if not exclude:match("^/") then
        exclude = root .. "/" .. exclude
    end
    local text = table.concat(vim.fn.filereadable(exclude) == 1 and vim.fn.readfile(exclude) or {}, "\n")
    local add = {}
    for _, pattern in ipairs({ "/compile_commands.json", "/.cache/" }) do
        if not text:find(pattern, 1, true) then
            table.insert(add, pattern)
        end
    end
    if #add > 0 then
        vim.fn.mkdir(vim.fs.dirname(exclude), "p")
        vim.fn.writefile(add, exclude, "a")
    end
end

local function restart_clangd()
    vim.lsp.enable("clangd", false)
    vim.lsp.enable("clangd", true)
end

local function ubt(root, extra, on_exit)
    local engine = engine_root()
    if not engine then
        vim.notify("unreal: no engine (set $UE_ROOT)", vim.log.levels.ERROR)
        return
    end
    local cmd = {
        engine .. "/Engine/Build/BatchFiles/Linux/Build.sh",
        editor_target(root),
        "Linux",
        "Development",
        "-Project=" .. uproject(root),
    }
    vim.list_extend(cmd, extra)
    vim.system(cmd, { text = true, cwd = root }, vim.schedule_wrap(on_exit))
end

function M.clangdb(root)
    vim.notify("unreal: generating compile_commands.json")
    ubt(root, { "-mode=GenerateClangDatabase", "-OutputDir=" .. root }, function(res)
        if res.code ~= 0 then
            vim.notify("unreal: GenerateClangDatabase failed\n" .. (res.stdout or ""):sub(-2000), vim.log.levels.ERROR)
            return
        end
        git_exclude(root)
        restart_clangd()
        vim.notify("unreal: compile_commands.json ready")
    end)
end

function M.build(root)
    vim.notify("unreal: building " .. editor_target(root))
    ubt(root, {}, function(res)
        local lines = vim.split((res.stdout or "") .. (res.stderr or ""), "\n")
        vim.fn.setqflist({}, " ", { title = "UnrealBuildTool", lines = lines, efm = "%f:%l:%c: %t%*[^:]: %m,%-G%.%#" })
        if res.code == 0 then
            vim.notify("unreal: build succeeded")
        else
            vim.notify("unreal: build failed", vim.log.levels.ERROR)
            vim.cmd("copen")
        end
    end)
end

function M.editor(root)
    if vim.fn.executable("unreal-editor") == 0 then
        vim.notify("unreal: no unreal-editor launcher", vim.log.levels.ERROR)
        return
    end
    vim.system({ "unreal-editor", uproject(root) }, { detach = true })
end

local function attach(path)
    local root = project_root(path)
    if not root then
        return
    end
    if not done[root] then
        done[root] = true
        if stale(root) then
            M.clangdb(root)
        end
    end
    local buf = vim.api.nvim_get_current_buf()
    local function map(lhs, fn, desc)
        vim.keymap.set("n", lhs, function()
            fn(root)
        end, { buffer = buf, desc = desc })
    end
    map("<leader>Ub", M.build, "Unreal: build editor target")
    map("<leader>Ue", M.editor, "Unreal: open editor")
    map("<leader>Ug", M.clangdb, "Unreal: regenerate compile_commands.json")
    pcall(function()
        require("which-key").add({ { "<leader>U", group = "unreal", buffer = buf } })
    end)
end

function M.setup()
    local group = vim.api.nvim_create_augroup("unreal", { clear = true })
    vim.api.nvim_create_autocmd("BufEnter", {
        group = group,
        callback = function(args)
            local name = vim.api.nvim_buf_get_name(args.buf)
            attach(name ~= "" and vim.fs.dirname(name) or vim.fn.getcwd())
        end,
    })
    vim.api.nvim_create_autocmd("BufWritePost", {
        group = group,
        pattern = { "*.Build.cs", "*.Target.cs", "*.uproject" },
        callback = function(args)
            local root = project_root(vim.fs.dirname(vim.api.nvim_buf_get_name(args.buf)))
            if root then
                M.clangdb(root)
            end
        end,
    })
end

return M
