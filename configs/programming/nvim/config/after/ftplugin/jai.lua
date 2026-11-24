if vim.fn.executable("jails") == 1 then
    vim.lsp.start({
        name = "jails",
        cmd = { "jails", "-jai_path", vim.env.HOME .. "/.jai", "-jai_exe_name", "jai-linux" },
        root_dir = vim.fs.root(0, { "jails.json", ".git" }) or vim.fn.getcwd(),
        handlers = {
            -- jails logs a missing jails.json as an error though it runs fine without one
            ["window/logMessage"] = function(err, params, ctx)
                if params.message:find("Failed to find 'jails.json'", 1, true) then
                    params.type = vim.lsp.protocol.MessageType.Info
                end
                return vim.lsp.handlers["window/logMessage"](err, params, ctx)
            end,
        },
    })
end
