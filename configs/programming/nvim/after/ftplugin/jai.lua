-- no mason package for jails, so start it per buffer
if vim.fn.executable("jails") == 1 then
    vim.lsp.start({
        name = "jails",
        cmd = { "jails", "-jai_path", vim.env.HOME .. "/.jai", "-jai_exe_name", "jai-linux" },
        root_dir = vim.fs.root(0, { "jails.json", ".git" }) or vim.fn.getcwd(),
    })
end
