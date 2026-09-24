-- :LPromptBuffer / :LPromptSelection Send buffer/selection text to the one hermes agent this editor owns.
local M = {}

local HERMES_AGENT_NAME = "lprompt-hermes"

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

local function herdr_json(args)
    local out = vim.system(args, { text = true }):wait()
    if out.code ~= 0 then
        return nil, vim.trim(out.stderr or out.stdout or "")
    end
    local ok, decoded = pcall(vim.json.decode, out.stdout)
    if not ok then
        return nil, "could not parse herdr output"
    end
    return decoded
end

local hermes_pane = nil

local function lookup_hermes()
    local decoded, err = herdr_json({ "herdr", "agent", "list" })
    if not decoded then
        return nil, "herdr agent list failed: " .. (err or "")
    end

    local agents = decoded.result and decoded.result.agents or {}
    for _, agent in ipairs(agents) do
        if agent.name == HERMES_AGENT_NAME
            or agent.id == HERMES_AGENT_NAME
            or agent.agent == HERMES_AGENT_NAME
        then
            return agent.pane_id
        end
    end
    return nil
end

local function find_or_start_hermes_target()
    if vim.fn.executable("herdr") == 0 then
        return nil, "herdr not on PATH"
    end

    local existing, err = lookup_hermes()
    if err then
        return nil, err
    end
    if existing then
        hermes_pane = existing
        return existing
    end

    local split, split_err = herdr_json({ "herdr", "pane", "split", "--direction", "right" })
    local new_pane_id = split and split.result and split.result.pane and split.result.pane.pane_id
    if not new_pane_id then
        return nil, "herdr pane split failed: " .. (split_err or "")
    end

    local start = vim.system(
        { "herdr", "agent", "start", HERMES_AGENT_NAME, "--kind", "hermes", "--pane", new_pane_id },
        { text = true }
    ):wait()
    if start.code ~= 0 then
        local raced = lookup_hermes()
        if raced then
            hermes_pane = raced
            return raced
        end
        return nil, "herdr agent start failed: " .. vim.trim(start.stderr or start.stdout or "")
    end

    hermes_pane = new_pane_id
    return new_pane_id
end

local function send_to_hermes(text)
    text = vim.trim(text)
    if text == "" then
        vim.notify("LPrompt: nothing to send (empty text)", vim.log.levels.WARN)
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
        hermes_pane = nil
        vim.notify(
            "LPrompt: herdr agent prompt failed: " .. vim.trim(prompt.stderr or prompt.stdout or ""),
            vim.log.levels.WARN
        )
    end
end

local function buffer_text()
    return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
end

local function selection_text(start_line, end_line)
    return table.concat(vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false), "\n")
end

function M.prompt_buffer()
    send_to_hermes(buffer_text())
end

function M.prompt_selection(start_line, end_line)
    send_to_hermes(selection_text(start_line, end_line))
end

function M.prompt_buffer_to_taskwarrior()
    add_prompt(buffer_text())
end

function M.prompt_selection_to_taskwarrior(start_line, end_line)
    add_prompt(selection_text(start_line, end_line))
end

function M.setup()
    vim.api.nvim_create_user_command("LPromptBuffer", function()
        M.prompt_buffer()
    end, { desc = "Send current buffer to the lprompt hermes agent" })

    vim.api.nvim_create_user_command("LPromptSelection", function(opts)
        M.prompt_selection(opts.line1, opts.line2)
    end, { range = true, desc = "Send visual selection to the lprompt hermes agent" })

    vim.api.nvim_create_user_command("LPromptBufferToTaskwarrior", function()
        M.prompt_buffer_to_taskwarrior()
    end, { desc = "Add current buffer as a +prompt taskwarrior task" })

    vim.api.nvim_create_user_command("LPromptSelectionToTaskwarrior", function(opts)
        M.prompt_selection_to_taskwarrior(opts.line1, opts.line2)
    end, { range = true, desc = "Add visual selection as a +prompt taskwarrior task" })
end

return M
