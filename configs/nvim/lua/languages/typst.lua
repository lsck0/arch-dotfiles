-- tinymist lsp starts via mason automatic_enable (see lsp.lua)
return {
    {
        "chomosuke/typst-preview.nvim", -- live browser preview for typst
        ft = "typst",
        version = "1.*",
        build = function() require("typst-preview").update() end,
    },
}
