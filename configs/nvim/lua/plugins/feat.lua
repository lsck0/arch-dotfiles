return {
    {
        "ej-shafran/compile-mode.nvim",
        branch = "latest",
        dependencies = {
            { "m00qek/baleia.nvim", tag = "v1.3.0" },
        },
        config = function()
            vim.g.compile_mode = {
                baleia_setup = true,
            }
        end
    },

    {
        "nvim-pack/nvim-spectre",
        config = function()
            require('spectre').setup()
        end
    },
}
