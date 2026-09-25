-- image.nvim queries the terminal for the kitty graphics protocol at startup.
local function terminal_graphics()
    if vim.g.neovide then return false end
    local term = vim.env.TERM or ""
    return vim.env.GHOSTTY_RESOURCES_DIR ~= nil
        or vim.env.KITTY_WINDOW_ID ~= nil
        or term:find("kitty", 1, true) ~= nil
end

return {
    {
        -- Round-trip .ipynb <-> markdown so notebooks open as plain text buffers.
        "GCBallesteros/jupytext.nvim",
        event = { "BufReadCmd *.ipynb" }, -- load before its own BufReadCmd converts the notebook
        opts = {
            -- percent, not markdown: an .ipynb round-trips to a .py with `# %%` cell markers.
            style = "percent",
            output_extension = "auto",
            force_ft = nil,
        },
    },
    {
        -- Run notebook/python cells inside nvim via a Jupyter kernel, with inline plots.
        "benlubas/molten-nvim",
        version = "^1.0.0",
        build = ":UpdateRemotePlugins",
        dependencies = {
            {
                -- molten renders plots through image.nvim.
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
            -- no kitty graphics (neovide, plain terminal): text-only output, no image.nvim, no crash.
            vim.g.molten_image_provider = terminal_graphics() and "image.nvim" or "none"
            vim.g.molten_output_win_max_height = 20
            vim.g.molten_auto_open_output = false
            vim.g.molten_wrap_output = true
            vim.g.molten_virt_text_output = true  -- show output as virtual text below the cell
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
