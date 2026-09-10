return {
  apply = function()
    require("lazy.core.loader").load("dracula.nvim", { plugin = "dracula.nvim" })
    vim.cmd("colorscheme dracula")
  end,
}
