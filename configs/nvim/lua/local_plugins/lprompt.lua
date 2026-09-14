-- :LPromptBuffer / :LPromptSelection
-- Send buffer/selection text into the nearest project's taskwarrior db as a +prompt task.
-- (see l-agent-task-db / l-multi-agent-task-mode)
local M = {}

local function find_taskrc(start_dir)
    local dir = start_dir
    while dir and dir ~= "" do
        local candidate = dir .. "/tasks/.taskrc"
        if vim.fn.filereadable(candidate) == 1 then
            return candidate
        end
        local parent = vim.fn.fnamemodify(dir, ":h")
        if parent == dir then
            return nil
        end
        dir = parent
    end
    return nil
end

local function add_prompt(text)
    text = vim.trim(text)
    if text == "" then
        vim.notify("LPrompt: nothing to add (empty text)", vim.log.levels.WARN)
        return
    end

    local start_dir = vim.fn.expand("%:p:h")
    if start_dir == "" then
        start_dir = vim.fn.getcwd()
    end
    local taskrc = find_taskrc(start_dir)
    if not taskrc then
        vim.notify(
            "LPrompt: no tasks/.taskrc found above " .. start_dir
            .. " -- scaffold one first (l-agent-task-db's taskwarrior-init)",
            vim.log.levels.ERROR
        )
        return
    end

    local result = vim.system(
        { "task", "rc:" .. taskrc, "add", "+prompt", "--", text },
        { text = true }
    ):wait()

    if result.code ~= 0 then
        vim.notify(
            "LPrompt: task add failed (" .. result.code .. "): " .. vim.trim(result.stderr or ""),
            vim.log.levels.ERROR
        )
        return
    end
    vim.notify("LPrompt: " .. vim.trim(result.stdout or "added"), vim.log.levels.INFO)
end

local function find_or_start_hermes_target()
    if vim.fn.executable("herdr") == 0 then
        return nil, "herdr not on PATH"
    end

    local list = vim.system({ "herdr", "agent", "list" }, { text = true }):wait()
    if list.code ~= 0 then
        return nil, "herdr agent list failed: " .. vim.trim(list.stderr or list.stdout or "")
    end

    local ok, decoded = pcall(vim.json.decode, list.stdout)
    if ok and decoded and decoded.result and decoded.result.agents then
        for _, agent in ipairs(decoded.result.agents) do
            if agent.agent == "hermes" then
                return agent.pane_id
            end
        end
    end

    local split = vim.system({ "herdr", "pane", "split", "--direction", "right" }, { text = true }):wait()
    local ok2, pane_decoded = pcall(vim.json.decode, split.stdout)
    local new_pane_id = ok2 and pane_decoded and pane_decoded.result and pane_decoded.result.pane
        and pane_decoded.result.pane.pane_id
    if split.code ~= 0 or not new_pane_id then
        return nil, "herdr pane split failed: " .. vim.trim(split.stderr or split.stdout or "")
    end

    local start = vim.system(
        { "herdr", "agent", "start", "lprompt-hermes", "--kind", "hermes", "--pane", new_pane_id },
        { text = true }
    ):wait()
    if start.code ~= 0 then
        return nil, "herdr agent start failed: " .. vim.trim(start.stderr or start.stdout or "")
    end
    return new_pane_id
end

local function send_to_hermes(text)
    text = vim.trim(text)
    if text == "" then
        return
    end
    local target, err = find_or_start_hermes_target()
    if not target then
        vim.notify("LPrompt: hermes forward skipped (" .. err .. ")", vim.log.levels.WARN)
        return
    end
    local prompt = vim.system(
        { "herdr", "agent", "prompt", target, text },
        { text = true }
    ):wait()
    if prompt.code ~= 0 then
        vim.notify(
            "LPrompt: herdr agent prompt failed: " .. vim.trim(prompt.stderr or prompt.stdout or ""),
            vim.log.levels.WARN
        )
    end
end

function M.prompt_buffer()
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local text = table.concat(lines, "\n")
    add_prompt(text)
    send_to_hermes(text)
end

function M.prompt_selection(start_line, end_line)
    local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
    local text = table.concat(lines, "\n")
    add_prompt(text)
    send_to_hermes(text)
end

function M.setup()
    vim.api.nvim_create_user_command("LPromptBuffer", function()
        M.prompt_buffer()
    end, { desc = "Add current buffer as a +prompt taskwarrior task and forward to hermes" })

    vim.api.nvim_create_user_command("LPromptSelection", function(opts)
        M.prompt_selection(opts.line1, opts.line2)
    end, { range = true, desc = "Add visual selection as a +prompt taskwarrior task and forward to hermes" })
end

return M
