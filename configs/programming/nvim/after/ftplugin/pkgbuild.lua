-- makepkg sources it with bash
vim.b.is_bash = 1
vim.bo.commentstring = "# %s"
vim.bo.comments = ":#"
-- :make lints with namcap: "PKGBUILD (name) W: message"
vim.bo.makeprg = "namcap %"
vim.bo.errorformat = "%f (%*[^)]) %t: %m"
