vim.keymap.set("n", "<C-s>", "<cmd>w<CR>", { desc = "Save file" })
vim.keymap.set("i", "<C-c>", "<ESC>", { desc = "Escape insert mode" })
vim.keymap.set("t", "<C-e>", [[<C-\><C-n>]], { desc = "Exit terminal mode" })

vim.keymap.set('n', '<M-q>', '@', { noremap = true, desc = "Apply macro (@)" })

if vim.g.neovide then
    local function scale(factor)
        vim.g.neovide_scale_factor = vim.g.neovide_scale_factor * factor
    end
    vim.keymap.set("n", "<C-=>", function() scale(1.1) end, { desc = "Neovide zoom in" })
    vim.keymap.set("n", "<C-+>", function() scale(1.1) end, { desc = "Neovide zoom in" })
    vim.keymap.set("n", "<C-->", function() scale(1 / 1.1) end, { desc = "Neovide zoom out" })
    vim.keymap.set("n", "<C-0>", function() vim.g.neovide_scale_factor = 1.0 end, { desc = "Neovide zoom reset" })
end

vim.keymap.set("n", "<Esc>", "<cmd>nohlsearch<CR>", { desc = "Clear search highlight" })

vim.keymap.set("n", "<leader>x", "<cmd>normal gcc<CR>", { desc = "Comment line" })
vim.keymap.set("v", "<leader>x", "<ESC><cmd>normal gvgc<CR>", { desc = "Comment selection" })

vim.keymap.set("n", "<C-d>", "<C-d>zz", { desc = "Half page down (centered)" })
vim.keymap.set("n", "<C-u>", "<C-u>zz", { desc = "Half page up (centered)" })
vim.keymap.set("n", "n", "nzzzv", { desc = "Next search match (centered)" })
vim.keymap.set("n", "N", "Nzzzv", { desc = "Prev search match (centered)" })

vim.keymap.set("n", "<M-t>", function() Snacks.terminal.toggle() end, { desc = "Toggle terminal (float)" })
vim.keymap.set("n", "<M-w>", function() Snacks.bufdelete() end, { desc = "Close buffer (keep layout)" })
vim.keymap.set("n", "<M-x>", "<cmd>tabclose <CR>", { desc = "Close tab" })
vim.keymap.set("n", "<M-c>", "<cmd>tabnew <CR>", { desc = "New tab" })
vim.keymap.set("n", "<M-1>", "<cmd>tabn 1<CR>", { desc = "Go to tab 1" })
vim.keymap.set("n", "<M-2>", "<cmd>tabn 2<CR>", { desc = "Go to tab 2" })
vim.keymap.set("n", "<M-3>", "<cmd>tabn 3<CR>", { desc = "Go to tab 3" })
vim.keymap.set("n", "<M-4>", "<cmd>tabn 4<CR>", { desc = "Go to tab 4" })
vim.keymap.set("n", "<M-5>", "<cmd>tabn 5<CR>", { desc = "Go to tab 5" })

-- deferred require: smart-splits lazy-loads on first use
vim.keymap.set("n", "<C-h>", function() require("smart-splits").resize_left() end, { desc = "Resize split left" })
vim.keymap.set("n", "<C-j>", function() require("smart-splits").resize_down() end, { desc = "Resize split down" })
vim.keymap.set("n", "<C-k>", function() require("smart-splits").resize_up() end, { desc = "Resize split up" })
vim.keymap.set("n", "<C-l>", function() require("smart-splits").resize_right() end, { desc = "Resize split right" })
vim.keymap.set("n", "<leader>w", "<cmd>WinShift<CR>", { desc = "Move window (WinShift)" })

vim.keymap.set("n", "<C-n>", "<cmd>cnext<CR>", { desc = "Next quickfix item" })
vim.keymap.set("n", "<C-S-n>", "<cmd>cprev<CR>", { desc = "Prev quickfix item" })
vim.keymap.set("n", "<C-t>", "<cmd>lua require('trouble').next({ skip_groups = true, jump = true })<CR>",
    { desc = "Next trouble item" })
vim.keymap.set("n", "<C-S-t>", "<cmd>lua require('trouble').prev({ skip_groups = true, jump = true })<CR>",
    { desc = "Prev trouble item" })

-- deferred require: telescope lazy-loads on first use
local function tb(fn, args)
    return function() require("telescope.builtin")[fn](args) end
end
vim.keymap.set("n", "<leader>fc", tb("find_files", { cwd = "~/projects/arch-dotfiles" }),
    { desc = "Find files (dotfiles)" })
vim.keymap.set("n", "<leader>ff", tb("find_files"), { desc = "Find files" })
vim.keymap.set("n", "<leader>fw", tb("live_grep"), { desc = "Live grep" })
vim.keymap.set("n", "<leader>fb", tb("buffers"), { desc = "Buffers" })
vim.keymap.set("n", "<leader>f*", tb("grep_string"), { desc = "Grep word under cursor" })
vim.keymap.set("n", "<leader>le", tb("diagnostics"), { desc = "Diagnostics (telescope)" })
vim.keymap.set("n", "<leader>lf", tb("lsp_references"), { desc = "LSP references" })
vim.keymap.set("n", "<leader>ls", tb("lsp_dynamic_workspace_symbols"), { desc = "Workspace symbols" })
vim.keymap.set("n", "<leader>lF", function() require("conform").format({ async = true, lsp_format = "fallback" }) end,
    { desc = "Format buffer" })
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
        local o = { buffer = ev.buf, remap = false }
        local function map(lhs, rhs, desc)
            vim.keymap.set("n", lhs, rhs, vim.tbl_extend("force", o, { desc = desc }))
        end
        map("<leader>ld", vim.lsp.buf.definition, "Go to definition")
        map("<leader>li", vim.lsp.buf.hover, "Hover info")
        map("<leader>lo", vim.diagnostic.open_float, "Open diagnostic float")
        map("<leader>la", vim.lsp.buf.code_action, "Code action")
        map("<leader>ln", function() vim.diagnostic.jump({ count = 1, float = true }) end, "Next diagnostic")
        map("<leader>lr", vim.lsp.buf.rename, "Rename symbol")
    end,
})

vim.api.nvim_set_keymap('n', '<leader>v', "<cmd>lua Toggle_venn()<CR>",
    { noremap = true, desc = "Toggle venn (draw boxes)" })
function _G.Toggle_venn()
    if not vim.b.venn_enabled then
        vim.b.venn_enabled = true
        vim.cmd [[setlocal ve=all]]
        vim.api.nvim_buf_set_keymap(0, "n", "<S-Down>", "<C-v>j:VBox<CR>", { noremap = true })
        vim.api.nvim_buf_set_keymap(0, "n", "<S-Up>", "<C-v>k:VBox<CR>", { noremap = true })
        vim.api.nvim_buf_set_keymap(0, "n", "<S-Right>", "<C-v>l:VBox<CR>", { noremap = true })
        vim.api.nvim_buf_set_keymap(0, "n", "<S-Left>", "<C-v>h:VBox<CR>", { noremap = true })
        vim.api.nvim_buf_set_keymap(0, "v", "f", ":VBox<CR>", { noremap = true })
    else
        vim.cmd [[setlocal ve=none]]
        vim.api.nvim_buf_del_keymap(0, "n", "<S-Down>")
        vim.api.nvim_buf_del_keymap(0, "n", "<S-Up>")
        vim.api.nvim_buf_del_keymap(0, "n", "<S-Right>")
        vim.api.nvim_buf_del_keymap(0, "n", "<S-Left>")
        vim.api.nvim_buf_del_keymap(0, "v", "f")
        vim.b.venn_enabled = nil
    end
end

vim.keymap.set("n", "<leader>dt", function()
    -- dapui errors when dap is not loaded yet
    require("dap")
    require("dapui").toggle()
end, { desc = "Toggle DAP UI" })
vim.keymap.set("n", "<leader>b", "<cmd>DapToggleBreakpoint<CR>", { desc = "Toggle breakpoint" })
vim.keymap.set("n", "<leader>B", "<cmd>lua require('dap').set_breakpoint(vim.fn.input('Condition: '))<CR>",
    { desc = "Conditional breakpoint" })
vim.keymap.set("n", "<F5>", "<cmd>DapContinue<CR>", { desc = "Debug: continue" })
vim.keymap.set("n", "<F10>", "<cmd>DapStepOver<CR>", { desc = "Debug: step over" })
vim.keymap.set("n", "<F11>", "<cmd>DapStepInto<CR>", { desc = "Debug: step into" })
vim.keymap.set("n", "<F12>", "<cmd>DapStepOut<CR>", { desc = "Debug: step out" })

vim.keymap.set("n", "<leader>e", function()
    local open = require("snacks.picker").get({ source = "explorer" })
    if open and #open > 0 then
        open[1]:close()
    else
        require("lib.explorer").open()
    end
end, { desc = "File explorer (snacks)" })
vim.keymap.set("n", "<leader>gs", "<cmd>G<CR>", { desc = "Git (fugitive)" })
vim.keymap.set("n", "<leader>gg", function() Snacks.lazygit() end, { desc = "Lazygit" })
vim.keymap.set("n", "<leader>gy", function() Snacks.gitbrowse() end, { desc = "Open line on GitHub" })
vim.keymap.set("n", "<leader>O", "<cmd>Oil . --float <CR>", { desc = "Oil file manager (float)" })
vim.keymap.set("n", "<leader>ss", "<cmd>lua require('grug-far').open()<CR>", { desc = "Search/replace (grug-far)" })
vim.keymap.set("n", "<leader>sw",
    "<cmd>lua require('grug-far').open({ prefills = { search = vim.fn.expand('<cword>') } })<CR>",
    { desc = "Search/replace word under cursor" })
vim.keymap.set("n", "<leader>tt", "<cmd>Trouble diagnostics<CR>", { desc = "Trouble diagnostics" })
vim.keymap.set("n", "<leader>ts", "<cmd>Trouble symbols toggle<CR>", { desc = "Trouble symbols" })
vim.keymap.set("n", "<leader>tl", "<cmd>Trouble lsp toggle<CR>", { desc = "Trouble LSP references" })
vim.keymap.set("n", "m", "<cmd>belowright Compile<CR>", { desc = "Compile (compile-mode)" })

vim.api.nvim_create_user_command("Perf", function(o)
    local file = (o.args ~= "" and o.args) or "perf.data"
    local esc = vim.fn.shellescape(file)
    local collapser = vim.fn.executable("stackcollapse-perf.pl") == 1 and "stackcollapse-perf.pl"
        or (vim.fn.executable("inferno-collapse-perf") == 1 and "inferno-collapse-perf" or nil)
    if file:match("%.data$") or file == "perf.data" then
        if collapser then
            vim.cmd("botright 20split | terminal perf script -i " .. esc .. " | " .. collapser .. " | flamelens")
            vim.cmd("startinsert")
        else
            vim.fn.jobstart({ "hotspot", file }, { detach = true }) -- gui, reads perf.data natively
        end
    else
        vim.cmd("botright 20split | terminal flamelens " .. esc) -- already-collapsed/folded stacks
        vim.cmd("startinsert")
    end
end, { nargs = "?", complete = "file", desc = "Explore perf dump (flamelens/hotspot)" })

vim.api.nvim_create_user_command("PerfGui", function(o)
    vim.fn.jobstart({ "hotspot", (o.args ~= "" and o.args) or "perf.data" }, { detach = true })
end, { nargs = "?", complete = "file", desc = "Open perf.data in hotspot (GUI)" })

vim.keymap.set("n", "<leader>pf", "<cmd>Perf<CR>", { desc = "Perf flamegraph (flamelens)" })
vim.keymap.set("n", "<leader>pg", "<cmd>PerfGui<CR>", { desc = "Perf in hotspot (GUI)" })

vim.api.nvim_create_user_command("CargoFlamegraph", function(o)
    local args = o.args ~= "" and (" " .. o.args) or ""
    vim.cmd("botright 20split | terminal cargo flamegraph" .. args)
    vim.cmd("startinsert")
end, { nargs = "*", desc = "cargo flamegraph (writes flamegraph.svg)" })

vim.api.nvim_create_user_command("PerfRecord", function(o)
    vim.cmd("botright 20split | terminal perf record -g -- " .. o.args)
    vim.cmd("startinsert")
end, { nargs = "+", complete = "shellcmd", desc = "perf record -g a command -> perf.data" })

vim.keymap.set("n", "<leader>pc", "<cmd>CargoFlamegraph<CR>", { desc = "cargo flamegraph" })
vim.keymap.set("n", "<leader>pr", ":PerfRecord ", { desc = "perf record a command" })

-- cycle buffer tabs (barbar); note: shadows <C-i> jump on <Tab>
vim.keymap.set("n", "<Tab>", "<cmd>BufferNext<CR>", { desc = "Next buffer" })
vim.keymap.set("n", "<S-Tab>", "<cmd>BufferPrevious<CR>", { desc = "Prev buffer" })
