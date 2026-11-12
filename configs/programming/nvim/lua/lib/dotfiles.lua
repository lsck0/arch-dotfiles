-- the dotfiles checkout: $DOTFILES, unset outside a uwsm session (tty, ssh), else where the config link resolves
return vim.env.DOTFILES or (vim.uv.fs_realpath(vim.fn.stdpath("config")) .. "/../../..")
