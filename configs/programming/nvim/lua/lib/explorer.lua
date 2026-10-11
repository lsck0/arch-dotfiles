-- tcd, then open without cwd: differing cwd forms stacked duplicate roots
local M = {}

---@return snacks.Picker|nil
local function explorer()
    local picker = require("snacks.picker").get({ source = "explorer" })[1]
    if picker and not picker.closed then return picker end
end

--- Open (or re-root) the explorer at DIR, defaulting to the current working directory. Unlike before it never
--- climbs to the enclosing git repo: the tree roots exactly where you are, so entering a subdir or a nested crate
--- keeps the root there instead of jumping up to the parent repo.
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

--- Expand the tree down to FILE and put the cursor on it, without moving focus.
---
--- snacks' own `follow_file` is off: its reveal re-roots the tree at the file's own directory when the file
--- sits outside the explorer cwd, which stacked a second root every time a file outside the repo was opened.
--- This only ever reveals inside the current root and leaves anything else alone.
function M.reveal(file)
    local picker = explorer()
    if not picker then return end
    if picker:is_focused() or not picker:on_current_tab() then return end

    file = vim.fs.normalize(file)
    if not require("snacks.explorer.tree"):in_cwd(picker:cwd(), file) then return end

    local item = picker:current()
    if item and item.file == file then return end

    require("snacks.explorer.actions").update(picker, { target = file })
end

--- Reveal the file shown in the current window. Non-file buffers (help, terminals, the picker itself) and
--- floats are skipped, so the tree never follows something the cursor is only passing through.
function M.reveal_current()
    if not explorer() then return end

    local win = vim.api.nvim_get_current_win()
    if vim.api.nvim_win_get_config(win).relative ~= "" then return end

    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].buftype ~= "" then return end

    local file = vim.api.nvim_buf_get_name(buf)
    if file == "" or vim.uv.fs_stat(file) == nil then return end

    M.reveal(file)
end

return M
