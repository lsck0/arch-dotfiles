vim.keymap.set("n", "<C-s>", "<cmd>w<CR>", { desc = "Save file" })
vim.keymap.set("i", "<C-c>", "<ESC>", { desc = "Escape insert mode" })
-- a double Esc, not C-e: zsh, lazygit and Claude Code need C-e, and a single Esc still reaches the program
vim.keymap.set("t", "<Esc><Esc>", [[<C-\><C-n>]], { desc = "Exit terminal mode" })

vim.keymap.set("n", "<M-x>", "@", { desc = "Apply macro (@)" })

if vim.g.neovide then
    local ZOOM_STEP = 1.1
    local function scale(factor)
        vim.g.neovide_scale_factor = vim.g.neovide_scale_factor * factor
    end
    for _, lhs in ipairs({ "<C-=>", "<C-+>" }) do
        vim.keymap.set("n", lhs, function()
            scale(ZOOM_STEP)
        end, { desc = "Neovide zoom in" })
    end
    vim.keymap.set("n", "<C-->", function()
        scale(1 / ZOOM_STEP)
    end, { desc = "Neovide zoom out" })
    vim.keymap.set("n", "<C-0>", function()
        vim.g.neovide_scale_factor = 1.0
    end, { desc = "Neovide zoom reset" })
end

vim.keymap.set("n", "<Esc>", "<cmd>nohlsearch<CR>", { desc = "Clear search highlight" })

vim.keymap.set("n", "<leader>x", "<cmd>normal gcc<CR>", { desc = "Comment line" })
vim.keymap.set("v", "<leader>x", "<ESC><cmd>normal gvgc<CR>", { desc = "Comment selection" })

vim.keymap.set("n", "<C-d>", "<C-d>zz", { desc = "Half page down (centered)" })
vim.keymap.set("n", "<C-u>", "<C-u>zz", { desc = "Half page up (centered)" })
vim.keymap.set("n", "n", "nzzzv", { desc = "Next search match (centered)" })
vim.keymap.set("n", "N", "Nzzzv", { desc = "Prev search match (centered)" })

vim.keymap.set("n", "<M-t>", "<cmd>lua Snacks.terminal.toggle()<CR>", { desc = "Toggle terminal (float)" })
vim.keymap.set("n", "<M-w>", "<cmd>lua Snacks.bufdelete()<CR>", { desc = "Close buffer (keep layout)" })
vim.keymap.set("n", "<M-q>", "<cmd>tabclose <CR>", { desc = "Close tab" })
vim.keymap.set("n", "<M-c>", "<cmd>tabnew <CR>", { desc = "New tab" })
for i = 1, 5 do
    vim.keymap.set("n", "<M-" .. i .. ">", "<cmd>tabn " .. i .. "<CR>", { desc = "Go to tab " .. i })
end

for key, dir in pairs({ h = "left", j = "down", k = "up", l = "right" }) do
    vim.keymap.set("n", "<C-" .. key .. ">", function()
        require("smart-splits")["resize_" .. dir]()
    end, { desc = "Resize split " .. dir })
    -- tmux's pane keys: past the last split they move on to the next tmux pane
    vim.keymap.set("n", "<M-" .. key:upper() .. ">", function()
        require("smart-splits")["move_cursor_" .. dir]()
    end, { desc = "Move to split " .. dir })
end
vim.keymap.set("n", "<leader>w", "<cmd>WinShift<CR>", { desc = "Move window (WinShift)" })

local function quickfix_cycle(step, wrap)
    if vim.fn.getqflist({ size = 0 }).size == 0 then
        return vim.notify("quickfix list is empty")
    end
    if not pcall(vim.cmd[step]) then
        vim.cmd[wrap]()
    end
end
local function trouble_cycle(step, wrap)
    local view = require("trouble").open({ refresh = false })
    if not view then
        return
    end
    local actions = require("trouble.config.actions")
    view:action(function(self, ctx)
        local row = vim.api.nvim_win_get_cursor(self.win.win)[1]
        actions[step](self, ctx)
        if vim.api.nvim_win_get_cursor(self.win.win)[1] == row then
            actions[wrap](self, ctx)
        end
    end, { jump = true })
end
vim.keymap.set("n", "<C-n>", function()
    quickfix_cycle("cnext", "cfirst")
end, { desc = "Next quickfix item" })
vim.keymap.set("n", "<C-S-n>", function()
    quickfix_cycle("cprev", "clast")
end, { desc = "Prev quickfix item" })
vim.keymap.set("n", "]t", function()
    trouble_cycle("next", "first")
end, { desc = "Next trouble item" })
vim.keymap.set("n", "[t", function()
    trouble_cycle("prev", "last")
end, { desc = "Prev trouble item" })

local function tb(fn, args)
    return function()
        require("telescope.builtin")[fn](args)
    end
end
vim.keymap.set(
    "n",
    "<leader>fc",
    tb("find_files", { cwd = require("lib.dotfiles") }),
    { desc = "Find files (dotfiles)" }
)
vim.keymap.set("n", "<leader>ff", tb("find_files"), { desc = "Find files" })
vim.keymap.set("n", "<leader>fw", tb("live_grep"), { desc = "Live grep" })
vim.keymap.set("n", "<leader>fb", tb("buffers"), { desc = "Buffers" })
vim.keymap.set("n", "<leader>f*", tb("grep_string"), { desc = "Grep word under cursor" })
vim.keymap.set("n", "<leader>fC", "<cmd>lua require('lib.citation').pick()<CR>", { desc = "Citations (insert key)" })
vim.keymap.set("n", "<leader>fp", "<cmd>lua require('lib.projects').pick()<CR>", { desc = "Projects" })
vim.keymap.set("n", "<leader>le", tb("diagnostics"), { desc = "Diagnostics (telescope)" })
vim.keymap.set("n", "<leader>lf", tb("lsp_references"), { desc = "LSP references" })
vim.keymap.set("n", "<leader>ls", tb("lsp_dynamic_workspace_symbols"), { desc = "Workspace symbols" })
vim.keymap.set("n", "<leader>lF", function()
    require("conform").format({ async = true, lsp_format = "fallback" })
end, { desc = "Format buffer" })
local virtual_text_saved
vim.keymap.set("n", "<leader>lv", function()
    local config = vim.diagnostic.config()
    if config.virtual_lines then
        vim.diagnostic.config({ virtual_lines = false, virtual_text = virtual_text_saved })
    else
        virtual_text_saved = config.virtual_text
        vim.diagnostic.config({ virtual_lines = { current_line = false }, virtual_text = false })
    end
end, { desc = "Toggle virtual_lines diagnostics" })

vim.api.nvim_create_autocmd("LspAttach", {
    group = vim.api.nvim_create_augroup("lsp-keymaps", { clear = true }),
    callback = function(ev)
        pcall(vim.lsp.inlay_hint.enable, true, { bufnr = ev.buf })
        local function map(lhs, rhs, desc)
            vim.keymap.set("n", lhs, rhs, { buffer = ev.buf, desc = desc })
        end
        map("<leader>ld", vim.lsp.buf.definition, "Go to definition")
        map("<leader>li", vim.lsp.buf.hover, "Hover info")
        map("<leader>lo", vim.diagnostic.open_float, "Open diagnostic float")
        map("<leader>la", vim.lsp.buf.code_action, "Code action")
        map("<leader>ln", function()
            vim.diagnostic.jump({ count = 1, float = true })
        end, "Next diagnostic")
        map("<leader>lr", vim.lsp.buf.rename, "Rename symbol")
    end,
})

local function toggle_venn()
    local boxes = { Down = "j", Up = "k", Right = "l", Left = "h" }
    if not vim.b.venn_enabled then
        vim.b.venn_enabled = true
        vim.cmd("setlocal ve=all")
        for arrow, motion in pairs(boxes) do
            vim.keymap.set("n", "<S-" .. arrow .. ">", "<C-v>" .. motion .. ":VBox<CR>", { buffer = 0 })
        end
        vim.keymap.set("v", "f", ":VBox<CR>", { buffer = 0 })
    else
        vim.cmd("setlocal ve=")
        for arrow in pairs(boxes) do
            vim.keymap.del("n", "<S-" .. arrow .. ">", { buffer = 0 })
        end
        vim.keymap.del("v", "f", { buffer = 0 })
        vim.b.venn_enabled = nil
    end
end
vim.keymap.set("n", "<leader>v", toggle_venn, { desc = "Toggle venn (draw boxes)" })

vim.keymap.set("n", "<leader>dt", function()
    -- dapui errors when dap is not loaded yet
    require("dap")
    require("dapui").toggle()
end, { desc = "Toggle DAP UI" })
vim.keymap.set("n", "<leader>b", "<cmd>DapToggleBreakpoint<CR>", { desc = "Toggle breakpoint" })
vim.keymap.set(
    "n",
    "<leader>B",
    "<cmd>lua require('dap').set_breakpoint(vim.fn.input('Condition: '))<CR>",
    { desc = "Conditional breakpoint" }
)
vim.keymap.set("n", "<F5>", "<cmd>DapContinue<CR>", { desc = "Debug: continue" })
vim.keymap.set("n", "<F10>", "<cmd>DapStepOver<CR>", { desc = "Debug: step over" })
vim.keymap.set("n", "<F11>", "<cmd>DapStepInto<CR>", { desc = "Debug: step into" })
vim.keymap.set("n", "<F12>", "<cmd>DapStepOut<CR>", { desc = "Debug: step out" })

vim.keymap.set("n", "<leader>e", "<cmd>lua require('lib.explorer').toggle()<CR>", { desc = "File explorer (snacks)" })
vim.keymap.set("n", "<leader>gs", "<cmd>G<CR>", { desc = "Git (fugitive)" })
vim.keymap.set("n", "<leader>gg", "<cmd>lua Snacks.lazygit()<CR>", { desc = "Lazygit" })
vim.keymap.set("n", "<leader>gy", "<cmd>lua Snacks.gitbrowse()<CR>", { desc = "Open line on GitHub" })
vim.keymap.set("n", "<leader>gf", "<cmd>lua require('lib.worktree').pick()<CR>", { desc = "Git worktrees" })
vim.keymap.set(
    "n",
    "<leader>gc",
    "<cmd>lua require('lib.worktree').pick_branch()<CR>",
    { desc = "Git worktree for branch (switch or create)" }
)
vim.api.nvim_create_user_command("Worktree", function(o)
    require("lib.worktree").add(o.args)
end, { nargs = 1, desc = "Switch to or create the worktree for a branch" })
vim.keymap.set("n", "<leader>O", "<cmd>Oil . --float <CR>", { desc = "Oil file manager (float)" })
vim.keymap.set("n", "<leader>ss", "<cmd>lua require('grug-far').open()<CR>", { desc = "Search/replace (grug-far)" })
vim.keymap.set(
    "n",
    "<leader>sw",
    "<cmd>lua require('grug-far').open({ prefills = { search = vim.fn.expand('<cword>') } })<CR>",
    { desc = "Search/replace word under cursor" }
)
vim.keymap.set("n", "<leader>tt", "<cmd>Trouble diagnostics<CR>", { desc = "Trouble diagnostics" })
vim.keymap.set("n", "<leader>ts", "<cmd>Trouble symbols toggle<CR>", { desc = "Trouble symbols" })
vim.keymap.set("n", "<leader>tl", "<cmd>Trouble lsp toggle<CR>", { desc = "Trouble LSP references" })
-- m shadows the builtin mark command on purpose: compile-mode muscle memory wins here
vim.keymap.set("n", "m", "<cmd>belowright Compile<CR>", { desc = "Compile (compile-mode)" })

local function term(cmd)
    vim.cmd("botright 20split | terminal " .. cmd)
    vim.cmd("startinsert")
end

vim.api.nvim_create_user_command("Perf", function(o)
    local file = (o.args ~= "" and o.args) or "perf.data"
    local esc = vim.fn.shellescape(file)
    local collapser = vim.fn.executable("stackcollapse-perf.pl") == 1 and "stackcollapse-perf.pl"
        or (vim.fn.executable("inferno-collapse-perf") == 1 and "inferno-collapse-perf" or nil)
    if file:match("%.data$") then
        if collapser then
            term("perf script -i " .. esc .. " | " .. collapser .. " | flamelens")
        else
            vim.fn.jobstart({ "hotspot", file }, { detach = true })
        end
    else
        term("flamelens " .. esc)
    end
end, { nargs = "?", complete = "file", desc = "Explore perf dump (flamelens/hotspot)" })

vim.api.nvim_create_user_command("PerfGui", function(o)
    vim.fn.jobstart({ "hotspot", (o.args ~= "" and o.args) or "perf.data" }, { detach = true })
end, { nargs = "?", complete = "file", desc = "Open perf.data in hotspot (GUI)" })

vim.keymap.set("n", "<leader>pf", "<cmd>Perf<CR>", { desc = "Perf flamegraph (flamelens)" })
vim.keymap.set("n", "<leader>pg", "<cmd>PerfGui<CR>", { desc = "Perf in hotspot (GUI)" })

vim.api.nvim_create_user_command("CargoFlamegraph", function(o)
    term("cargo flamegraph" .. (o.args ~= "" and (" " .. o.args) or ""))
end, { nargs = "*", desc = "cargo flamegraph (writes flamegraph.svg)" })

vim.api.nvim_create_user_command("PerfRecord", function(o)
    term("perf record -g -- " .. o.args)
end, { nargs = "+", complete = "shellcmd", desc = "perf record -g a command -> perf.data" })

vim.keymap.set("n", "<leader>pc", "<cmd>CargoFlamegraph<CR>", { desc = "cargo flamegraph" })
vim.keymap.set("n", "<leader>pr", ":PerfRecord ", { desc = "perf record a command" })

-- not Tab: where the terminal sends Tab and C-i alike it would take jump-forward
vim.keymap.set("n", "]b", "<cmd>BufferNext<CR>", { desc = "Next buffer" })
vim.keymap.set("n", "[b", "<cmd>BufferPrevious<CR>", { desc = "Prev buffer" })
