-- pywal.nvim only sets its own groups: without the clear and the name, a switch kept the last theme's
-- remaining groups and lualine kept loading that theme
vim.cmd.highlight("clear")
if vim.g.syntax_on then
    vim.cmd.syntax("reset")
end
require("pywal").setup()
vim.g.colors_name = "wal"
