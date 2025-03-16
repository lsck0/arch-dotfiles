-- ctrl + s for saving
vim.keymap.set("n", "<C-s>", "<cmd>w<CR>")

-- commenting
vim.keymap.set("n", "<leader>x", "<cmd>normal gcc<CR>")
vim.keymap.set("v", "<leader>x", "<ESC><cmd>normal gvgc<CR>")

-- m for running the compile command
vim.keymap.set("n", "m", "<cmd>belowright Compile<CR>")

-- easier macros
vim.keymap.set('n', '<M-q>', '@', { noremap = true })

-- esc for leaving insert mode in terminal
vim.keymap.set("t", "<C-e>", [[<C-\><C-n>]])

-- make jump commands also center the screen
vim.keymap.set("n", "<C-d>", "<C-d>zz")
vim.keymap.set("n", "<C-u>", "<C-u>zz")
vim.keymap.set("n", "n", "nzzzv")
vim.keymap.set("n", "N", "Nzzzv")

-- quickfix/trouble list navigation
vim.keymap.set("n", "<C-n>", "<cmd>cnext<CR>")
vim.keymap.set("n", "<C-S-n>", "<cmd>cprev<CR>")
vim.keymap.set("n", "<C-t>", "<cmd>lua require('trouble').next({ skip_groups = true, jump = true })<CR>")
vim.keymap.set("n", "<C-S-t>", "<cmd>lua require('trouble').prev({ skip_groups = true, jump = true })<CR>")

-- tab navigation + terminal
vim.keymap.set("n", "<M-t>", "<cmd>terminal <CR>")
vim.keymap.set("n", "<M-x>", "<cmd>tabclose <CR>")
vim.keymap.set("n", "<M-c>", "<cmd>tabnew <CR>")
vim.keymap.set("n", "<M-1>", "<cmd>tabn 1<CR>")
vim.keymap.set("n", "<M-2>", "<cmd>tabn 2<CR>")
vim.keymap.set("n", "<M-3>", "<cmd>tabn 3<CR>")
vim.keymap.set("n", "<M-4>", "<cmd>tabn 4<CR>")
vim.keymap.set("n", "<M-5>", "<cmd>tabn 5<CR>")

-- resize splits
vim.keymap.set("n", "<C-h>", require("smart-splits").resize_left)
vim.keymap.set("n", "<C-j>", require("smart-splits").resize_down)
vim.keymap.set("n", "<C-k>", require("smart-splits").resize_up)
vim.keymap.set("n", "<C-l>", require("smart-splits").resize_right)
vim.keymap.set("n", "<leader>w", "<cmd>WinShift<CR>")

-- popouts
vim.keymap.set("n", "<leader>e", "<cmd>Neotree toggle left<CR>")
vim.keymap.set("n", "<leader>g", "<cmd>G<CR>")
vim.keymap.set("n", "<leader>s", "<cmd>lua require('spectre').toggle()<CR>", {})
vim.keymap.set("n", "<leader>sw", "<cmd>lua require('spectre').open_visual({select_word=true})<CR>", {})
vim.keymap.set("n", "<leader>t", "<cmd>Trouble diagnostics<CR>")
vim.keymap.set("n", "<leader>o", "<cmd>Oil . --float <CR>")

-- telescope and lsp
local telescope = require("telescope.builtin")
local opts = { buffer = bufnr, remap = false }
vim.keymap.set("n", "<leader>fc", function()
    telescope.find_files({
        cwd = "~/code/arch-dotfiles",
    })
end, {})

vim.keymap.set("n", "<leader>ff", telescope.find_files, {})
vim.keymap.set("n", "<leader>fw", telescope.live_grep, {})
vim.keymap.set("n", "<leader>fb", telescope.buffers, {})
vim.keymap.set("n", "<leader>f*", telescope.grep_string, {})
vim.keymap.set("n", "<leader>le", telescope.diagnostics, {})
vim.keymap.set("n", "<leader>lf", telescope.lsp_references, {})
vim.keymap.set("n", "<leader>ld", vim.lsp.buf.definition)
vim.keymap.set("n", "<leader>li", vim.lsp.buf.hover, opts)
vim.keymap.set("n", "<leader>lo", vim.diagnostic.open_float, opts)
vim.keymap.set("n", "<leader>la", vim.lsp.buf.code_action, opts)
vim.keymap.set("n", "<leader>ln", vim.diagnostic.goto_next, opts)
vim.keymap.set("n", "<leader>lr", vim.lsp.buf.rename, opts)

-- venn.nvim
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

vim.api.nvim_set_keymap('n', '<leader>v', "<cmd>lua Toggle_venn()<CR>", { noremap = true })

-- chat commands
vim.keymap.set("n", "<leader>cf", "<cmd>GpChatFinder<cr>")
vim.keymap.set("n", "<leader>cn", "<cmd>GpChatNew<cr>")
vim.keymap.set("n", "<leader>ct", "<cmd>GpChatToggle<cr>")
vim.keymap.set("n", "<leader>cc", "<cmd>GpChatRespond<cr>")
vim.keymap.set("v", "<leader>cd", "<cmd>GpChatDelete<cr>")
vim.keymap.set("v", "<leader>cn", ":<C-u>'<,'>GpChatNew<cr>")
vim.keymap.set("v", "<leader>cp", ":<C-u>'<,'>GpChatPaste<cr>")
vim.keymap.set("v", "<leader>ct", ":<C-u>'<,'>GpChatToggle<cr>")

-- prompt commands
vim.keymap.set("n", "<leader>ca", "<cmd>GpAppend<cr>")
vim.keymap.set("n", "<leader>cp", "<cmd>GpPopup<cr>")
vim.keymap.set("n", "<leader>cr", "<cmd>GpRewrite<cr>")
vim.keymap.set("v", "<leader>ca", ":<C-u>'<,'>GpAppend<cr>")
vim.keymap.set("v", "<leader>ci", ":<C-u>'<,'>GpImplement<cr>")
vim.keymap.set("v", "<leader>cp", ":<C-u>'<,'>GpPopup<cr>")
vim.keymap.set("v", "<leader>cr", ":<C-u>'<,'>GpRewrite<cr>")

-- debugging
vim.keymap.set("n", "<leader>dt", "<cmd>lua require('dapui').toggle()<CR>")
vim.keymap.set("n", "<leader>b", "<cmd>DapToggleBreakpoint<CR>")
vim.keymap.set("n", "<leader>B", "<cmd>ua require('dap').set_breakpoint(vim.fn.input('Condition: '))<CR>")
vim.keymap.set("n", "<F5>", "<cmd>DapContinue<CR>")
vim.keymap.set("n", "<F10>", "<cmd>DapStepOver<CR>")
vim.keymap.set("n", "<F11>", "<cmd>DapStepInto<CR>")
vim.keymap.set("n", "<F12>", "<cmd>DapStepOut<CR>")
