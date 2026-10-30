local installed = require("lib.mason_packages")

return {
    {
        "folke/lazydev.nvim",
        ft = "lua",
        opts = {
            library = {
                { path = "${3rd}/luv/library", words = { "vim%.uv" } },
            },
        },
    },

    {
        "mason-org/mason.nvim",
        event = { "BufReadPre", "BufNewFile" },
        cmd = {
            "Mason",
            "MasonInstall",
            "MasonUninstall",
            "MasonUpdate",
            "MasonLog",
            "MasonToolsInstall",
            "MasonToolsInstallSync",
            "MasonToolsUpdate",
        },
        dependencies = {
            { "neovim/nvim-lspconfig" },
            { "mason-org/mason-lspconfig.nvim" },
            { "WhoIsSethDaniel/mason-tool-installer.nvim" },
            { "marilari88/twoslash-queries.nvim" },
            { "ivanjermakov/troublesum.nvim", opts = {} },
            { "Sebastian-Nielsen/better-type-hover", opts = {} },
            { "dmmulroy/ts-error-translator.nvim", opts = {} },
        },
        config = function()
            vim.diagnostic.config({
                severity_sort = true,
                virtual_text = {
                    prefix = "\u{25cf}",
                    spacing = 2,
                    source = "if_many",
                },
                float = {
                    source = "if_many",
                    header = "",
                },
                signs = {
                    text = {
                        [vim.diagnostic.severity.ERROR] = vim.fn.nr2char(0xea87), -- nf-cod-error
                        [vim.diagnostic.severity.WARN] = vim.fn.nr2char(0xea6c), -- nf-cod-warning
                        [vim.diagnostic.severity.INFO] = vim.fn.nr2char(0xea74), -- nf-cod-info
                        [vim.diagnostic.severity.HINT] = vim.fn.nr2char(0xea61), -- nf-cod-lightbulb
                    },
                },
            })

            require("mason").setup()
            -- uv setenv, scoped to installs: the events fire in a fast context and :terminal keeps the system luarocks
            local registry = require("mason-registry")
            local luarocks_config = vim.fn.stdpath("config") .. "/luarocks.lua"
            local installs = 0
            local saved_config = nil
            registry:on("package:install:handle", function()
                if installs == 0 then
                    saved_config = vim.uv.os_getenv("LUAROCKS_CONFIG")
                    vim.uv.os_setenv("LUAROCKS_CONFIG", luarocks_config)
                end
                installs = installs + 1
            end)
            local function install_end()
                installs = installs - 1
                assert(installs >= 0, "mason install end without a start")
                if installs == 0 then
                    if saved_config then
                        vim.uv.os_setenv("LUAROCKS_CONFIG", saved_config)
                    else
                        vim.uv.os_unsetenv("LUAROCKS_CONFIG")
                    end
                end
            end
            registry:on("package:install:success", install_end)
            registry:on("package:install:failed", install_end)
            require("mason-tool-installer").setup({
                ensure_installed = installed,
                run_on_start = true,
            })
            -- lazy-loaded on a later buffer, VimEnter has already fired then
            if vim.v.vim_did_enter == 1 then
                require("mason-tool-installer").run_on_start()
            end
            -- same engine candidates as unreal.lua's engine_root, so a driver found via $UE_ROOT or $XDG_DATA_HOME
            -- also gets its system includes extracted
            local ue_data = vim.env.XDG_DATA_HOME or (vim.env.HOME .. "/.local/share")
            local ue_dirs = { ue_data .. "/unreal-engine", "/opt/unreal-engine" }
            if vim.env.UE_ROOT then
                table.insert(ue_dirs, 1, vim.env.UE_ROOT)
            end
            local query_drivers = {}
            for _, dir in ipairs(ue_dirs) do
                query_drivers[#query_drivers + 1] = dir .. "/**/bin/clang++"
            end
            vim.lsp.config("clangd", {
                cmd = {
                    "clangd",
                    "--offset-encoding=utf-16",
                    "--background-index",
                    "--query-driver=" .. table.concat(query_drivers, ","),
                },
            })

            local cobol_jar = vim.fn.stdpath("data")
                .. "/mason/packages/cobol-language-support/extension/server/jar/server.jar"
            if vim.uv.fs_stat(cobol_jar) then
                vim.lsp.config("cobol_ls", { cmd = { "java", "-jar", cobol_jar } })
                vim.lsp.enable("cobol_ls")
            end

            vim.lsp.config("nushell", {
                cmd = {
                    "nu",
                    "--no-config-file",
                    "-I",
                    -- $DOTFILES is unset in a non-uwsm session (tty, ssh); the config link resolves into the repo
                    (os.getenv("DOTFILES") or (vim.uv.fs_realpath(vim.fn.stdpath("config")) .. "/../../.."))
                        .. "/scripts/lib",
                    "--lsp",
                },
            })
            vim.lsp.enable("nushell")

            -- kani projects need these cfgs and nightly, plain rust must not get them
            local function rust_extra_env(root)
                local f = type(root) == "string" and io.open(root .. "/Cargo.toml")
                if f then
                    local uses_kani = f:read("*a"):find("kani") ~= nil
                    f:close()
                    if uses_kani then
                        return { RUSTFLAGS = "--cfg kani_ra --cfg kani", RUSTUP_TOOLCHAIN = "nightly" }
                    end
                end
                return vim.empty_dict()
            end

            local rust_analyzer_before_init = vim.lsp.config.rust_analyzer.before_init
            vim.lsp.config("rust_analyzer", {
                before_init = function(params, config)
                    local settings = config.settings["rust-analyzer"]
                    local env = rust_extra_env(config.root_dir)
                    settings.cargo.extraEnv = env
                    settings.check.extraEnv = env
                    rust_analyzer_before_init(params, config)
                end,
                settings = {
                    ["rust-analyzer"] = {
                        cargo = { allFeatures = true },
                        check = { command = "clippy" },
                    },
                },
            })

            vim.lsp.config("tailwindcss", {
                filetypes = {
                    "html",
                    "css",
                    "scss",
                    "less",
                    "javascript",
                    "javascriptreact",
                    "typescript",
                    "typescriptreact",
                    "vue",
                    "svelte",
                },
            })

            -- root at the typos config, else its allowlist is ignored
            vim.lsp.config("typos_lsp", {
                root_markers = { ".typos.toml", "_typos.toml", "typos.toml", ".git" },
                init_options = { config = vim.fn.expand("~/.config/typos/typos.toml") },
            })

            local vue_plugin = vim.fn.stdpath("data")
                .. "/mason/packages/vue-language-server/node_modules/@vue/language-server"
            vim.lsp.config("ts_ls", {
                filetypes = { "javascript", "javascriptreact", "typescript", "typescriptreact", "vue" },
                init_options = {
                    plugins = {
                        { name = "@vue/typescript-plugin", location = vue_plugin, languages = { "vue" } },
                    },
                },
                on_attach = {
                    vim.lsp.config.ts_ls.on_attach,
                    function(client, bufnr)
                        require("twoslash-queries").attach(client, bufnr)
                    end,
                },
            })

            -- system JDK: mise may pin an older java on PATH
            vim.lsp.config("jdtls", {
                cmd = { "jdtls", "--java-executable", "/usr/lib/jvm/default/bin/java" },
                init_options = {
                    bundles = vim.fn.glob(
                        vim.fn.stdpath("data")
                            .. "/mason/packages/java-debug-adapter/extension/server/com.microsoft.java.debug.plugin-*.jar",
                        true,
                        true
                    ),
                },
            })

            local ipython_builtins = {
                display = true,
                get_ipython = true,
                In = true,
                Out = true,
                exit = true,
                quit = true,
            }
            local function project_python(root)
                -- a json-null rootPath is vim.NIL, which is truthy
                if type(root) ~= "string" or root == "" then
                    return nil
                end
                local venv = vim.env.VIRTUAL_ENV
                if venv and vim.fn.executable(venv .. "/bin/python") == 1 then
                    return venv .. "/bin/python"
                end
                if vim.fn.executable(root .. "/.venv/bin/python") == 1 then
                    return root .. "/.venv/bin/python"
                end
                if vim.fn.filereadable(root .. "/pyproject.toml") == 1 and vim.fn.executable("poetry") == 1 then
                    local out = vim.trim(vim.fn.system({ "timeout", "2", "poetry", "-C", root, "env", "info", "-e" }))
                    if vim.v.shell_error == 0 and out ~= "" then
                        return out
                    end
                end
            end

            local function drop_ipython_noise(buf, diagnostics)
                if not vim.b[buf].is_jupytext then
                    return diagnostics
                end
                return vim.tbl_filter(function(d)
                    local name = d.code == "reportUndefinedVariable" and d.message:match('"([%w_]+)"')
                    return not (name and ipython_builtins[name])
                end, diagnostics)
            end

            local publish = vim.lsp.handlers["textDocument/publishDiagnostics"]
            local pull = vim.lsp.handlers["textDocument/diagnostic"]
            vim.lsp.config("pyright", {
                before_init = function(params, config)
                    local root = params.rootPath or (params.rootUri and vim.uri_to_fname(params.rootUri))
                    local py = project_python(root)
                    if py then
                        config.settings = config.settings or {}
                        config.settings.python = config.settings.python or {}
                        config.settings.python.pythonPath = py
                    end
                end,
                handlers = {
                    ["textDocument/publishDiagnostics"] = function(err, result, ctx)
                        result.diagnostics = drop_ipython_noise(vim.uri_to_bufnr(result.uri), result.diagnostics)
                        return publish(err, result, ctx)
                    end,
                    ["textDocument/diagnostic"] = function(err, result, ctx)
                        if result and result.items then
                            result.items = drop_ipython_noise(ctx.bufnr, result.items)
                        end
                        return pull(err, result, ctx)
                    end,
                },
            })

            vim.lsp.config("texlab", {
                settings = {
                    texlab = {
                        build = { onSave = false, forwardSearchAfter = false },
                        chktex = { onOpenAndSave = false, onEdit = false },
                        latexindent = { modifyLineBreaks = true },
                        diagnosticsDelay = 300,
                        diagnostics = { ignoredPatterns = { "^Unused entry" } },
                    },
                },
            })

            vim.lsp.config("bashls_pkgbuild", {
                cmd = { "bash-language-server", "start" },
                filetypes = { "pkgbuild" },
                root_markers = { "PKGBUILD" },
                settings = {
                    bashIde = { shellcheckArguments = { "--exclude=SC2034,SC2154,SC2164" } },
                },
            })
            vim.lsp.enable("bashls_pkgbuild")

            vim.lsp.enable("gdscript")

            -- cobol_ls excluded: mason's config would clobber the custom jar cmd
            require("mason-lspconfig").setup({
                automatic_enable = { exclude = { "cobol_ls" } },
            })
        end,
    },

    {
        "stevearc/conform.nvim",
        config = function()
            require("conform").formatters.sortderives = {
                inherit = false,
                command = vim.uv.fs_realpath(vim.fn.stdpath("config")) .. "/../formatting/sort-derives-stdout.nu",
                stdin = true,
            }
            require("conform").formatters["kulala-fmt"] = { command = "kulala-fmt" }
            require("conform").formatters.latexindent = { prepend_args = { "-m", "-g", "/dev/null" } }

            local formatting = vim.fs.dirname(vim.uv.fs_realpath(vim.fn.stdpath("config"))) .. "/formatting/"
            local function personal(names, flag, file)
                return function(_, ctx)
                    if vim.fs.find(names, { path = ctx.dirname, upward = true })[1] then
                        return {}
                    end
                    return { flag .. formatting .. file }
                end
            end
            require("conform").formatters["clang-format"] = {
                prepend_args = personal({ ".clang-format", "_clang-format" }, "--style=file:", "clang-format"),
            }
            require("conform").formatters.stylua = {
                prepend_args = personal({ "stylua.toml", ".stylua.toml" }, "--config-path=", "stylua.toml"),
            }
            require("conform").formatters.prettier = {
                prepend_args = personal({
                    ".prettierrc",
                    ".prettierrc.json",
                    ".prettierrc.json5",
                    ".prettierrc.yaml",
                    ".prettierrc.yml",
                    ".prettierrc.toml",
                    ".prettierrc.js",
                    ".prettierrc.cjs",
                    ".prettierrc.mjs",
                    ".prettierrc.ts",
                    "prettier.config.js",
                    "prettier.config.cjs",
                    "prettier.config.mjs",
                    "prettier.config.ts",
                }, "--config=", "prettierrc.json"),
            }
            -- the personal rustfmt.toml is nightly-only; a project's own config runs on its toolchain
            local rustfmt = personal({ "rustfmt.toml", ".rustfmt.toml" }, "--config-path=", "rustfmt.toml")
            require("conform").formatters.rustfmt = {
                prepend_args = function(self, ctx)
                    local args = rustfmt(self, ctx)
                    if args[1] then
                        table.insert(args, 1, "+nightly")
                    end
                    return args
                end,
            }
            local ruff = personal(function(name, path)
                if name == "ruff.toml" or name == ".ruff.toml" then
                    return true
                end
                return name == "pyproject.toml"
                    and vim.fn.readblob(path .. "/" .. name):find("[tool.ruff", 1, true) ~= nil
            end, "--config=", "ruff.toml")
            require("conform").formatters.ruff_format = { prepend_args = ruff }
            require("conform").formatters.ruff_organize_imports = { prepend_args = ruff }
            require("conform").formatters.php_cs_fixer = {
                prepend_args = function(_, ctx)
                    local configs = { ".php-cs-fixer.php", ".php-cs-fixer.dist.php" }
                    if vim.fs.find(configs, { path = ctx.dirname, upward = true })[1] then
                        return {}
                    end
                    return { "--rules=@PSR12" }
                end,
            }

            local formatters_by_ft = {
                bib = { "bibtex-tidy" },
                c = { "clang-format" },
                cpp = { "clang-format" },
                haskell = { "ormolu" },
                http = { "kulala-fmt" },
                plaintex = { "latexindent" },
                python = { "ruff_organize_imports", "ruff_format" },
                rest = { "kulala-fmt" },
                rust = function(bufnr)
                    local fmts = { "rustfmt", "sortderives" }
                    local root = vim.fs.root(bufnr, { "Cargo.toml" })
                    local f = root and io.open(root .. "/Cargo.toml")
                    if f then
                        if f:read("*a"):find("leptos") then
                            table.insert(fmts, "leptosfmt")
                        end
                        f:close()
                    end
                    return fmts
                end,
                tex = { "latexindent" },
                typst = { "typstyle" },
                lua = { "stylua" },
                sh = { "shfmt" },
                bash = { "shfmt" },
                pkgbuild = { "shfmt" },
                go = { "goimports", "gofumpt" },
                nix = { "nixfmt" },
                ruby = { "rubocop" },
                php = { "php_cs_fixer" },
                cs = { "csharpier" },
                kotlin = { "ktlint" },
                clojure = { "cljfmt" },
                elixir = { "mix" },
                sql = { "sql_formatter" },
            }
            for _, ft in ipairs({
                "css",
                "html",
                "javascript",
                "javascriptreact",
                "json",
                "jsonc",
                "markdown",
                "scss",
                "svelte",
                "typescript",
                "typescriptreact",
                "vue",
                "yaml",
                "graphql",
            }) do
                formatters_by_ft[ft] = { "prettier" }
            end

            require("conform").setup({
                formatters_by_ft = formatters_by_ft,
                format_on_save = function(bufnr)
                    if vim.g.disable_autoformat or vim.b[bufnr].disable_autoformat then
                        return
                    end
                    return { timeout_ms = 1000, lsp_format = "fallback" }
                end,
            })

            vim.api.nvim_create_user_command("FormatToggle", function(o)
                if o.bang then
                    vim.b.disable_autoformat = not vim.b.disable_autoformat
                else
                    vim.g.disable_autoformat = not vim.g.disable_autoformat
                end
                vim.notify("autoformat " .. ((vim.g.disable_autoformat or vim.b.disable_autoformat) and "off" or "on"))
            end, { bang = true, desc = "Toggle format-on-save (! = buffer only)" })
        end,
    },
}
