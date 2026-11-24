-- the explorer opens after a tcd and without a cwd: differing cwd forms stacked duplicate roots

local M = {}

-- get() also returns closed pickers, so a stale one must not count as open
---@return snacks.Picker|nil
local function explorer()
    local picker = require("snacks.picker").get({ source = "explorer" })[1]
    if picker and not picker.closed then
        return picker
    end
end

---@param dir? string
function M.open(dir)
    dir = dir and vim.fs.normalize(dir) or vim.uv.cwd()
    pcall(vim.cmd.tcd, vim.fn.fnameescape(dir))
    local picker = explorer()
    if picker then
        picker:set_cwd(dir)
        picker:find()
    else
        require("snacks").explorer()
    end
end

function M.toggle()
    local picker = explorer()
    if picker then
        picker:close()
    else
        M.open()
    end
end

-- Selects the current window's file in an open explorer on this tab, without re-rooting it.
function M.reveal_current()
    local picker = explorer()
    if not picker or picker:is_focused() or not picker:on_current_tab() then
        return
    end

    local win = vim.api.nvim_get_current_win()
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.api.nvim_win_get_config(win).relative ~= "" or vim.bo[buf].buftype ~= "" then
        return
    end

    local file = vim.api.nvim_buf_get_name(buf)
    if file == "" or vim.uv.fs_stat(file) == nil then
        return
    end
    file = vim.fs.normalize(file)
    if not require("snacks.explorer.tree"):in_cwd(picker:cwd(), file) then
        return
    end

    local item = picker:current()
    if not (item and item.file == file) then
        require("snacks.explorer.actions").update(picker, { target = file })
    end
end

return M
