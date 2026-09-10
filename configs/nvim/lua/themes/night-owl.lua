return {
  apply = function()
    require("lazy.core.loader").load("night-owl.nvim", { plugin = "night-owl.nvim" })
    vim.cmd("colorscheme night-owl")
  end,
}
