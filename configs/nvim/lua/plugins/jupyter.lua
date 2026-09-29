-- image.nvim needs the kitty graphics protocol
local function terminal_graphics()
    if vim.g.neovide then return false end
    local term = vim.env.TERM or ""
    return vim.env.GHOSTTY_RESOURCES_DIR ~= nil
        or vim.env.KITTY_WINDOW_ID ~= nil
        or term:find("kitty", 1, true) ~= nil
end

return {
    {
        -- open .ipynb as text
        "GCBallesteros/jupytext.nvim",
        event = { "BufReadCmd *.ipynb" }, -- load before its BufReadCmd runs
        opts = {
            -- .py with `# %%` cell markers
            style = "percent",
            output_extension = "auto",
            force_ft = nil,
        },
    },
    {
        -- run cells in a jupyter kernel
        "benlubas/molten-nvim",
        version = "^1.0.0",
        build = ":UpdateRemotePlugins",
        dependencies = {
            {
                "3rd/image.nvim",
                cond = terminal_graphics,
                opts = {
                    backend = "kitty",
                    processor = "magick_cli",
                },
            },
        },
        ft = { "python", "markdown", "quarto" },
        init = function()
            -- text-only output without kitty graphics
            vim.g.molten_image_provider = terminal_graphics() and "image.nvim" or "none"
            vim.g.molten_output_win_max_height = 20
            vim.g.molten_auto_open_output = false
            vim.g.molten_wrap_output = true
            vim.g.molten_virt_text_output = true
            vim.g.molten_virt_lines_off_by_1 = true
        end,
        keys = {
            { "<leader>ji", "<cmd>MoltenInit<cr>",              desc = "Init kernel" },
            { "<leader>je", "<cmd>MoltenEvaluateOperator<cr>",  desc = "Evaluate operator" },
            { "<leader>jl", "<cmd>MoltenEvaluateLine<cr>",      desc = "Evaluate line" },
            { "<leader>jv", ":<C-u>MoltenEvaluateVisual<cr>gv", mode = "v", desc = "Evaluate selection" },
            { "<leader>jr", "<cmd>MoltenReevaluateCell<cr>",    desc = "Re-evaluate cell" },
            { "<leader>jd", "<cmd>MoltenDelete<cr>",            desc = "Delete cell" },
            { "<leader>jo", "<cmd>MoltenShowOutput<cr>",        desc = "Show output" },
            { "<leader>jh", "<cmd>MoltenHideOutput<cr>",        desc = "Hide output" },
            { "<leader>jn", "<cmd>MoltenNext<cr>",              desc = "Next cell" },
            { "<leader>jp", "<cmd>MoltenPrev<cr>",              desc = "Previous cell" },
        },
    },
}
