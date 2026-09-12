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

function M.prompt_buffer()
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    add_prompt(table.concat(lines, "\n"))
end

function M.prompt_selection(start_line, end_line)
    local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
    add_prompt(table.concat(lines, "\n"))
end

function M.setup()
    vim.api.nvim_create_user_command("LPromptBuffer", function()
        M.prompt_buffer()
    end, { desc = "Add current buffer as a +prompt taskwarrior task" })

    vim.api.nvim_create_user_command("LPromptSelection", function(opts)
        M.prompt_selection(opts.line1, opts.line2)
    end, { range = true, desc = "Add visual selection as a +prompt taskwarrior task" })
end

return M
