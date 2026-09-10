return {
  apply = function()
    require("lazy.core.loader").load("gruvbox.nvim", { plugin = "gruvbox.nvim" })
    vim.cmd("colorscheme gruvbox")
  end,
}
