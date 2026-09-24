-- jails LSP for Jai: no mason package, so start it per-buffer.
vim.lsp.start({
    name = "jails",
    cmd = { "jails", "-jai_path", "/home/luca/.jai", "-jai_exe_name", "jai-linux" },
    root_dir = vim.fs.root(0, { "jails.json", ".git" }) or vim.fn.getcwd(),
})
