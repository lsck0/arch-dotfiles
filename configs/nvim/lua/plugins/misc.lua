return {
    { "TheZoq2/neovim-auto-autoread" },
    { "sitiom/nvim-numbertoggle" },
    {
        "chrisgrieser/nvim-early-retirement",
        config = function()
            require("early-retirement").setup({
                retirementAgeMins = 3,
            })
        end
    },
    {
        "ggandor/leap.nvim",
        config = function() require("leap").create_default_mappings() end
    },
    {
        "hat0uma/csvview.nvim",
        opts = {
            parser = { comments = { "#", "//" } },
        },
    },
    { "jbyuki/venn.nvim" },
    { "mrjones2014/smart-splits.nvim" },
    {
        "nacro90/numb.nvim",
        config = function() require("numb").setup() end
    },
    {
        "nosduco/remote-sshfs.nvim",
        dependencies = { "nvim-telescope/telescope.nvim", "nvim-lua/plenary.nvim" },
        config = function()
            require("remote-sshfs").setup()
        end
    },
    { "sindrets/winshift.nvim" },
    { "tpope/vim-repeat" },
    { "zeioth/garbage-day.nvim" },
    {
        "ziontee113/icon-picker.nvim",
        config = function() require("icon-picker").setup({ disable_legacy_commands = true }) end
    },
    {
        "laytan/cloak.nvim",
        config = function()
            require("cloak").setup({
                enabled = true,
                cloak_character =
                "#",
                highlight_group = "Comment",
                patterns = { { file_pattern = { "*.env*" }, cloak_pattern = "=.+" }, },
            })
        end
    },
    {
        "folke/twilight.nvim",
        opts = {
            treesitter = true,
            expand = {
                "enum_specifier",
                "for_statement",
                "function_definition",
                "if_statement",
                "preproc_function_def",
                "preproc_if",
                "struct_specifier",
                "type_definition",
                "while_statement",
            },
        }
    },
    {
        "folke/zen-mode.nvim",
        opts = {},
    },
}
