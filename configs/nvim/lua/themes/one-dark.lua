return {
  apply = function()
    require("lazy.core.loader").load("onedark.nvim", { plugin = "onedark.nvim" })
    vim.cmd("colorscheme onedark")
  end,
}
