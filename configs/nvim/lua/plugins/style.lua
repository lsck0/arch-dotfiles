-- Helpers for writing in l-style (section banners, doc comments).
return {
    {
        "LudoPinelli/comment-box.nvim", -- box/line existing text or a selection
        keys = {
            { "<leader>Cb", "<cmd>CBllbox<cr>",  mode = { "n", "v" }, desc = "Comment box (left)" },
            { "<leader>Cl", "<cmd>CBline<cr>",   desc = "Comment separator line" },
            { "<leader>Cc", "<cmd>CBcatalog<cr>", desc = "Comment-box catalog" },
            { "<leader>Cd", "<cmd>CBd<cr>",      mode = { "n", "v" }, desc = "Remove comment box/line" },
        },
        opts = { doc_width = 120, box_width = 100 },
    },

    {
        "danymat/neogen", -- generate doc-comment (annotation) skeletons
        cmd = "Neogen",
        keys = {
            { "<leader>Cn", function() require("neogen").generate() end, desc = "Generate doc comment" },
        },
        opts = {
            snippet_engine = "luasnip",
            languages = {
                c   = { template = { annotation_convention = "doxygen" } },
                cpp = { template = { annotation_convention = "doxygen" } },
            },
        },
    },
}
