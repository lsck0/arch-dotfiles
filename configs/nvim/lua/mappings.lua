-- ctrl + s for saving, ctrl + c for exiting insert mode, ctrl + e for exiting terminal mode
vim.keymap.set("n", "<C-s>", "<cmd>w<CR>", { desc = "Save file" })
vim.keymap.set("i", "<C-c>", "<ESC>", { desc = "Escape insert mode" })
vim.keymap.set("t", "<C-e>", [[<C-\><C-n>]], { desc = "Exit terminal mode" })

-- easier macros
vim.keymap.set('n', '<M-q>', '@', { noremap = true, desc = "Apply macro (@)" })

-- clear search highlight
vim.keymap.set("n", "<Esc>", "<cmd>nohlsearch<CR>", { desc = "Clear search highlight" })

-- commenting
vim.keymap.set("n", "<leader>x", "<cmd>normal gcc<CR>", { desc = "Comment line" })
vim.keymap.set("v", "<leader>x", "<ESC><cmd>normal gvgc<CR>", { desc = "Comment selection" })

-- make jump commands also center the screen
vim.keymap.set("n", "<C-d>", "<C-d>zz", { desc = "Half page down (centered)" })
vim.keymap.set("n", "<C-u>", "<C-u>zz", { desc = "Half page up (centered)" })
vim.keymap.set("n", "n", "nzzzv", { desc = "Next search match (centered)" })
vim.keymap.set("n", "N", "Nzzzv", { desc = "Prev search match (centered)" })

-- tab navigation + terminal
vim.keymap.set("n", "<M-t>", "<cmd>terminal <CR>", { desc = "New terminal" })
vim.keymap.set("n", "<M-x>", "<cmd>tabclose <CR>", { desc = "Close tab" })
vim.keymap.set("n", "<M-c>", "<cmd>tabnew <CR>", { desc = "New tab" })
vim.keymap.set("n", "<M-1>", "<cmd>tabn 1<CR>", { desc = "Go to tab 1" })
vim.keymap.set("n", "<M-2>", "<cmd>tabn 2<CR>", { desc = "Go to tab 2" })
vim.keymap.set("n", "<M-3>", "<cmd>tabn 3<CR>", { desc = "Go to tab 3" })
vim.keymap.set("n", "<M-4>", "<cmd>tabn 4<CR>", { desc = "Go to tab 4" })
vim.keymap.set("n", "<M-5>", "<cmd>tabn 5<CR>", { desc = "Go to tab 5" })

-- resize splits
vim.keymap.set("n", "<C-h>", require("smart-splits").resize_left, { desc = "Resize split left" })
vim.keymap.set("n", "<C-j>", require("smart-splits").resize_down, { desc = "Resize split down" })
vim.keymap.set("n", "<C-k>", require("smart-splits").resize_up, { desc = "Resize split up" })
vim.keymap.set("n", "<C-l>", require("smart-splits").resize_right, { desc = "Resize split right" })
vim.keymap.set("n", "<leader>w", "<cmd>WinShift<CR>", { desc = "Move window (WinShift)" })

-- quickfix/trouble list navigation
vim.keymap.set("n", "<C-n>", "<cmd>cnext<CR>", { desc = "Next quickfix item" })
vim.keymap.set("n", "<C-S-n>", "<cmd>cprev<CR>", { desc = "Prev quickfix item" })
vim.keymap.set("n", "<C-t>", "<cmd>lua require('trouble').next({ skip_groups = true, jump = true })<CR>",
    { desc = "Next trouble item" })
vim.keymap.set("n", "<C-S-t>", "<cmd>lua require('trouble').prev({ skip_groups = true, jump = true })<CR>",
    { desc = "Prev trouble item" })

-- telescope and lsp
local telescope = require("telescope.builtin")
local opts = { buffer = bufnr, remap = false }
vim.keymap.set("n", "<leader>fc", function()
    telescope.find_files({
        cwd = "~/projects/arch-dotfiles",
    })
end, { desc = "Find files (dotfiles)" })
vim.keymap.set("n", "<leader>ff", telescope.find_files, { desc = "Find files" })
vim.keymap.set("n", "<leader>fw", telescope.live_grep, { desc = "Live grep" })
vim.keymap.set("n", "<leader>fb", telescope.buffers, { desc = "Buffers" })
vim.keymap.set("n", "<leader>f*", telescope.grep_string, { desc = "Grep word under cursor" })
vim.keymap.set("n", "<leader>le", telescope.diagnostics, { desc = "Diagnostics (telescope)" })
vim.keymap.set("n", "<leader>lf", telescope.lsp_references, { desc = "LSP references" })
vim.keymap.set("n", "<leader>ld", vim.lsp.buf.definition, { desc = "Go to definition" })
vim.keymap.set("n", "<leader>li", vim.lsp.buf.hover, vim.tbl_extend("force", opts, { desc = "Hover info" }))
vim.keymap.set("n", "<leader>lo", vim.diagnostic.open_float,
    vim.tbl_extend("force", opts, { desc = "Open diagnostic float" }))
vim.keymap.set("n", "<leader>la", vim.lsp.buf.code_action, vim.tbl_extend("force", opts, { desc = "Code action" }))
vim.keymap.set("n", "<leader>ln", function() vim.diagnostic.jump({ count = 1, float = true }) end,
    vim.tbl_extend("force", opts, { desc = "Next diagnostic" }))
vim.keymap.set("n", "<leader>lr", vim.lsp.buf.rename, vim.tbl_extend("force", opts, { desc = "Rename symbol" }))

-- venn.nvim
vim.api.nvim_set_keymap('n', '<leader>v', "<cmd>lua Toggle_venn()<CR>",
    { noremap = true, desc = "Toggle venn (draw boxes)" })
function _G.Toggle_venn()
    local venn_enabled = vim.inspect(vim.b.venn_enabled)
    if venn_enabled == "nil" then
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

-- debugging
vim.keymap.set("n", "<leader>dt", "<cmd>lua require('dapui').toggle()<CR>", { desc = "Toggle DAP UI" })
vim.keymap.set("n", "<leader>b", "<cmd>DapToggleBreakpoint<CR>", { desc = "Toggle breakpoint" })
vim.keymap.set("n", "<leader>B", "<cmd>lua require('dap').set_breakpoint(vim.fn.input('Condition: '))<CR>",
    { desc = "Conditional breakpoint" })
vim.keymap.set("n", "<F5>", "<cmd>DapContinue<CR>", { desc = "Debug: continue" })
vim.keymap.set("n", "<F10>", "<cmd>DapStepOver<CR>", { desc = "Debug: step over" })
vim.keymap.set("n", "<F11>", "<cmd>DapStepInto<CR>", { desc = "Debug: step into" })
vim.keymap.set("n", "<F12>", "<cmd>DapStepOut<CR>", { desc = "Debug: step out" })

-- popouts
vim.keymap.set("n", "<leader>e", "<cmd>Neotree toggle left<CR>", { desc = "File tree (neo-tree)" })
vim.keymap.set("n", "<leader>g", "<cmd>G<CR>", { desc = "Git (fugitive)" })
vim.keymap.set("n", "<leader>o", "<cmd>Oil . --float <CR>", { desc = "Oil file manager (float)" })
vim.keymap.set("n", "<leader>s", "<cmd>lua require('spectre').toggle()<CR>", { desc = "Spectre search/replace" })
vim.keymap.set("n", "<leader>sw", "<cmd>lua require('spectre').open_visual({select_word=true})<CR>",
    { desc = "Spectre word under cursor" })
vim.keymap.set("n", "<leader>t", "<cmd>Trouble diagnostics<CR>", { desc = "Trouble diagnostics" })
vim.keymap.set("n", "m", "<cmd>belowright Compile<CR>", { desc = "Compile (compile-mode)" })
