-- catppuccin-mocha's own colors file, independent of the plugin's
-- `flavour = "mocha"` default set in ui.lua's setup() — this always applies
-- mocha specifically regardless of what that default is.
return {
  apply = function()
    require("lazy.core.loader").load("catppuccin", { plugin = "catppuccin" })
    vim.cmd("colorscheme catppuccin-mocha")
  end,
}
