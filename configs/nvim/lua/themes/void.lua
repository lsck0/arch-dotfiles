-- void theme (themes/void.json at repo root) has no dedicated nvim colorscheme of its own -- its palette is a tokyonight-night derivative, so reuse that plugin rather than inventing a new one.
return {
    apply = function()
        require("lazy.core.loader").load("tokyonight.nvim", { plugin = "tokyonight.nvim" })
        vim.cmd("colorscheme tokyonight-night")
    end,
}
