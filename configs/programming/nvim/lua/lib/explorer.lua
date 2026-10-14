-- tcd, then open without cwd: differing cwd forms stacked duplicate roots
local M = {}

---@return snacks.Picker|nil
local function explorer()
    local picker = require("snacks.picker").get({ source = "explorer" })[1]
    if picker and not picker.closed then
        return picker
    end
end

--- Open the explorer at DIR (default cwd), never climbing to the enclosing git repo.
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

--- Expand the tree down to FILE without moving focus, only inside the current root.
function M.reveal(file)
    local picker = explorer()
    if not picker then
        return
    end
    if picker:is_focused() or not picker:on_current_tab() then
        return
    end

    file = vim.fs.normalize(file)
    if not require("snacks.explorer.tree"):in_cwd(picker:cwd(), file) then
        return
    end

    local item = picker:current()
    if item and item.file == file then
        return
    end

    require("snacks.explorer.actions").update(picker, { target = file })
end

--- Skips non-file buffers and floats, so the tree never follows what the cursor only passes through.
function M.reveal_current()
    if not explorer() then
        return
    end

    local win = vim.api.nvim_get_current_win()
    if vim.api.nvim_win_get_config(win).relative ~= "" then
        return
    end

    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].buftype ~= "" then
        return
    end

    local file = vim.api.nvim_buf_get_name(buf)
    if file == "" or vim.uv.fs_stat(file) == nil then
        return
    end

    M.reveal(file)
end

return M
