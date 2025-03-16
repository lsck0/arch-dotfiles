return {
    { "LintaoAmons/scratch.nvim" },
    { "TheZoq2/neovim-auto-autoread" },
    {
        "chrisgrieser/nvim-early-retirement",
        config = function()
            require("early-retirement").setup({
                retirementAgeMins = 3,
            })
        end
    },
    {
        "echasnovski/mini.nvim",
        config = function()
            require("mini.ai").setup()
            require("mini.surround").setup({
                mappings = {
                    add = "ea",
                    delete = "ed",
                    replace = "er",
                    find = "ef",
                    find_left = "eF",
                    highlight = "eh",
                    update_n_lines = "en",
                }
            })
        end
    },
    {
        "folke/todo-comments.nvim",
        config = function() require("todo-comments").setup() end
    },
    {
        "folke/trouble.nvim",
        config = function()
            require("trouble").setup({ padding = false, })
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
    { "junegunn/vim-easy-align" },
    {
        "jiaoshijie/undotree",
        dependencies = "nvim-lua/plenary.nvim",
        config = true,
        keys = {
            { "<leader>u", "<cmd>lua require('undotree').toggle()<cr>" },
        },
    },
    {
        "laytan/cloak.nvim",
        config = function()
            require("cloak").setup({
                enabled = true,
                cloak_character =
                "#",
                highlight_group = "Comment",
                patterns = { { file_pattern = { ".env*", }, cloak_pattern = "=.+" }, },
            })
        end
    },
    { "matze/vim-move" },
    { "mrjones2014/smart-splits.nvim" },
    {
        "nacro90/numb.nvim",
        config = function() require("numb").setup() end
    },
    { "nicwest/vim-camelsnek" },
    { "sindrets/winshift.nvim" },
    { "tpope/vim-repeat" },
    {
        "yorickpeterse/nvim-pqf",
        config = function() require("pqf").setup() end
    },
    { "zeioth/garbage-day.nvim" },
    {
        "ziontee113/icon-picker.nvim",
        config = function() require("icon-picker").setup({ disable_legacy_commands = true }) end
    },
}
