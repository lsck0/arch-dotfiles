local mason_packages = require("lib.mason_packages")

-- vscode-json-language-server knows no schema by itself: the files a project commits most
local JSON_SCHEMAS = {
    { fileMatch = { "package.json" }, url = "https://json.schemastore.org/package.json" },
    { fileMatch = { "tsconfig.json", "tsconfig.*.json" }, url = "https://json.schemastore.org/tsconfig.json" },
    { fileMatch = { "jsconfig.json", "jsconfig.*.json" }, url = "https://json.schemastore.org/jsconfig.json" },
    { fileMatch = { ".eslintrc", ".eslintrc.json" }, url = "https://json.schemastore.org/eslintrc.json" },
    { fileMatch = { ".prettierrc", ".prettierrc.json" }, url = "https://json.schemastore.org/prettierrc.json" },
    {
        fileMatch = { ".babelrc", ".babelrc.json", "babel.config.json" },
        url = "https://json.schemastore.org/babelrc.json",
    },
    { fileMatch = { "composer.json" }, url = "https://getcomposer.org/schema.json" },
    {
        fileMatch = { ".luarc.json", ".luarc.jsonc" },
        url = "https://raw.githubusercontent.com/LuaLS/vscode-lua/master/setting/schema.json",
    },
}

-- taplo's default catalog (schemastore's) no longer parses in taplo 0.10, so no catalog and the files named here
local TOML_SCHEMAS = {
    ["(^|/)Cargo\\.toml$"] = "https://json.schemastore.org/cargo.json",
    ["(^|/)pyproject\\.toml$"] = "https://json.schemastore.org/pyproject.json",
    ["(^|/)\\.?rustfmt\\.toml$"] = "https://json.schemastore.org/rustfmt.json",
    ["(^|/)\\.?ruff\\.toml$"] = "https://json.schemastore.org/ruff.json",
    ["(^|/)\\.?taplo\\.toml$"] = "https://json.schemastore.org/taplo.json",
    ["(^|/)[._]?typos\\.toml$"] = "https://raw.githubusercontent.com/crate-ci/typos/master/config.schema.json",
}

-- a project's own prettier config, else the personal one is passed
local PRETTIER_CONFIGS = {
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
}
-- formatted on save only under a project's prettier config: the personal one rewraps prose and tables, and the
-- dotfiles gate (scripts/lib/gate.nu) leaves these alone
local PROJECT_FORMAT_FILETYPES = { json = true, jsonc = true, markdown = true }
-- lazy writes it one entry per line and rewrites it on every update
local FORMAT_SKIP_NAMES = { ["lazy-lock.json"] = true }
-- latexindent takes seconds on a long chapter: formatted after the write, so a save never waits or times out
local FORMAT_AFTER_SAVE_FILETYPES = { plaintex = true, tex = true }
local FORMAT_TIMEOUT_MS = 1000

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
            "MasonToolsUpdateSync",
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
        -- mason's bin on PATH from startup, not from its first buffer: conform, :checkhealth and jobs started before
        -- a file is read find the tools; setup skips its own prepend so the entry is not doubled
        init = function()
            vim.env.PATH = vim.fn.stdpath("data") .. "/mason/bin:" .. vim.env.PATH
        end,
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

            require("mason").setup({ PATH = "skip" })
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
                ensure_installed = vim.iter(ipairs(mason_packages))
                    :map(function(_, name)
                        local pin = mason_packages.pins[name]
                        return pin and { name, version = pin } or name
                    end)
                    :totable(),
                run_on_start = true,
            })
            -- lazy-loaded on a later buffer, VimEnter has already fired then
            if vim.v.vim_did_enter == 1 then
                require("mason-tool-installer").run_on_start()
            end
            -- an unreal engine's own clang++, so its system includes are extracted
            local query_drivers = {}
            for _, dir in ipairs(require("local_plugins.unreal").engine_dirs()) do
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
                    require("lib.dotfiles") .. "/scripts/lib",
                    "--lsp",
                },
            })
            vim.lsp.enable("nushell")

            -- quickshell imports its own config as qs.*: the same qs link the lint gate (scripts/lib/gate.nu) gives
            -- qmllint, else every qs import and the types it brings are unresolved
            if vim.fn.executable("qmlls6") == 1 then
                local qml_imports = vim.fn.stdpath("cache") .. "/qmlls-imports"
                local qs_tree = require("lib.dotfiles") .. "/configs/desktop/quickshell/config"
                -- a link left from before the tree moved into config/ is replaced
                if vim.uv.fs_readlink(qml_imports .. "/qs") ~= qs_tree then
                    vim.fn.mkdir(qml_imports, "p")
                    vim.uv.fs_unlink(qml_imports .. "/qs")
                    vim.uv.fs_symlink(qs_tree, qml_imports .. "/qs")
                end
                vim.lsp.config("qmlls", { cmd = { "qmlls6", "-I", qml_imports } })
                vim.lsp.enable("qmlls")
            end

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

            -- root at the typos config, else its allowlist is ignored; it takes every filetype, so a snacks bigfile is
            -- kept from it (the file's whole text would go to the server)
            local typos_roots = { ".typos.toml", "_typos.toml", "typos.toml", ".git" }
            vim.lsp.config("typos_lsp", {
                root_dir = function(bufnr, on_dir)
                    if vim.bo[bufnr].filetype == "bigfile" then
                        return
                    end
                    local root = vim.fs.root(bufnr, typos_roots)
                    if root then
                        return on_dir(root)
                    end
                    -- without a root lsp.start looks the markers up again a tick later, on a buffer a session load
                    -- may have wiped by then ("Invalid buffer id")
                    vim.schedule(function()
                        if vim.api.nvim_buf_is_valid(bufnr) then
                            on_dir(nil)
                        end
                    end)
                end,
                init_options = {
                    config = (vim.env.XDG_CONFIG_HOME or (vim.env.HOME .. "/.config")) .. "/typos/typos.toml",
                },
            })

            vim.lsp.config("taplo", {
                settings = {
                    evenBetterToml = { schema = { enabled = true, catalogs = {}, associations = TOML_SCHEMAS } },
                },
            })
            vim.lsp.config("jsonls", { settings = { json = { schemas = JSON_SCHEMAS, validate = { enable = true } } } })

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
                    local py = require("lib.python").find(root)
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

            -- fetches missing flake inputs itself, in place of a prompt on every open
            vim.lsp.config("nil_ls", { settings = { ["nil"] = { nix = { flake = { autoArchive = true } } } } })

            vim.lsp.config("texlab", {
                settings = {
                    texlab = {
                        build = { onSave = false, forwardSearchAfter = false },
                        chktex = { onOpenAndSave = true, onEdit = true },
                        latexindent = { modifyLineBreaks = true },
                        diagnosticsDelay = 300,
                        diagnostics = { ignoredPatterns = { "^Unused entry" } },
                    },
                },
                handlers = {
                    -- texlab takes the first didOpen before it pulled these settings, so chktex skips the opened
                    -- file; a didSave once they are answered runs it
                    ["workspace/configuration"] = function(err, params, ctx)
                        local answer = vim.lsp.handlers["workspace/configuration"](err, params, ctx)
                        vim.schedule(function()
                            local client = vim.lsp.get_client_by_id(ctx.client_id)
                            for bufnr in pairs(client and client.attached_buffers or {}) do
                                local document = { uri = vim.uri_from_bufnr(bufnr) }
                                client:notify("textDocument/didSave", { textDocument = document })
                            end
                        end)
                        return answer
                    end,
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

            -- servers pacman installs (toolchains, python, latex, formatting): mason-lspconfig enables only its own
            vim.lsp.enable({ "clangd", "ruff", "taplo", "texlab", "tinymist" })

            -- cobol_ls excluded: mason's config would clobber the custom jar cmd
            require("mason-lspconfig").setup({
                automatic_enable = { exclude = { "cobol_ls" } },
            })
        end,
    },

    {
        "stevearc/conform.nvim",
        event = "BufWritePre",
        cmd = { "ConformInfo", "FormatToggle" },
        config = function()
            local conform = require("conform")
            local formatters = conform.formatters
            local formatting = require("lib.dotfiles") .. "/configs/programming/formatting/"
            formatters.sortderives =
                { inherit = false, command = formatting .. "scripts/sort-derives-stdout.nu", stdin = true }
            formatters["kulala-fmt"] = { command = "kulala-fmt" }
            formatters.latexindent = { prepend_args = { "-m", "-g", "/dev/null" } }

            local function personal(names, flag, file)
                return function(_, ctx)
                    if vim.fs.find(names, { path = ctx.dirname, upward = true })[1] then
                        return {}
                    end
                    return { flag .. formatting .. "config/" .. file }
                end
            end
            formatters["clang-format"] = {
                prepend_args = personal({ ".clang-format", "_clang-format" }, "--style=file:", "clang-format"),
            }
            formatters.stylua = {
                prepend_args = personal({ "stylua.toml", ".stylua.toml" }, "--config-path=", "stylua.toml"),
            }
            formatters.prettier = { prepend_args = personal(PRETTIER_CONFIGS, "--config=", "prettierrc.json") }
            -- nixfmt reads no config: the width of Luca's style and the homelab's formatter check
            formatters.nixfmt = { prepend_args = { "--width=120" } }
            -- the personal rustfmt.toml is nightly-only; a project's own config runs on its toolchain
            local rustfmt = personal({ "rustfmt.toml", ".rustfmt.toml" }, "--config-path=", "rustfmt.toml")
            formatters.rustfmt = {
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
            formatters.ruff_format = { prepend_args = ruff }
            formatters.ruff_organize_imports = { prepend_args = ruff }
            -- plain text has no formatter of its own: fmt rewraps lines past 120 and never joins short ones, so lists,
            -- tables and hand-broken lines survive
            formatters.fmt_text = {
                command = "fmt",
                args = { "--split-only", "--width=120", "--goal=120" },
            }
            -- a @NAME@ template is not toml yet: taplo refuses it on every save, so it is skipped as the gate does
            formatters.taplo = {
                condition = function(_, ctx)
                    return not table.concat(vim.api.nvim_buf_get_lines(ctx.buf, 0, -1, false), "\n"):find("@[A-Z_]+@")
                end,
            }
            formatters.php_cs_fixer = {
                prepend_args = function(_, ctx)
                    local configs = { ".php-cs-fixer.php", ".php-cs-fixer.dist.php" }
                    if vim.fs.find(configs, { path = ctx.dirname, upward = true })[1] then
                        return {}
                    end
                    return { "--rules=@PSR12" }
                end,
            }

            local formatters_by_ft = {
                bash = { "shfmt" },
                bib = { "bibtex-tidy" },
                c = { "clang-format" },
                clojure = { "cljfmt" },
                cpp = { "clang-format" },
                cs = { "csharpier" },
                go = { "goimports", "gofumpt" },
                haskell = { "ormolu" },
                http = { "kulala-fmt" },
                kotlin = { "ktlint" },
                lua = { "stylua" },
                nix = { "nixfmt" },
                php = { "php_cs_fixer" },
                pkgbuild = { "shfmt" },
                plaintex = { "latexindent" },
                python = { "ruff_organize_imports", "ruff_format" },
                rest = { "kulala-fmt" },
                ruby = { "rubocop" },
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
                sh = { "shfmt" },
                sql = { "sql_formatter" },
                tex = { "latexindent" },
                text = { "fmt_text" },
                toml = { "taplo" },
                typst = { "typstyle" },
            }
            for _, ft in ipairs({
                "css",
                "graphql",
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
            }) do
                formatters_by_ft[ft] = { "prettier" }
            end

            ---@return "before"|"after"|nil
            local function format_when(bufnr)
                if vim.g.disable_autoformat or vim.b[bufnr].disable_autoformat then
                    return nil
                end
                local name = vim.api.nvim_buf_get_name(bufnr)
                if FORMAT_SKIP_NAMES[vim.fs.basename(name)] then
                    return nil
                end
                local ft = vim.bo[bufnr].filetype
                local dirname = vim.fs.dirname(name)
                if
                    PROJECT_FORMAT_FILETYPES[ft]
                    and not vim.fs.find(PRETTIER_CONFIGS, { path = dirname, upward = true })[1]
                then
                    return nil
                end
                return FORMAT_AFTER_SAVE_FILETYPES[ft] and "after" or "before"
            end

            conform.setup({
                formatters_by_ft = formatters_by_ft,
                format_on_save = function(bufnr)
                    local when = format_when(bufnr)
                    return when == "before" and { timeout_ms = FORMAT_TIMEOUT_MS, lsp_format = "fallback" } or nil
                end,
                format_after_save = function(bufnr)
                    return format_when(bufnr) == "after" and { lsp_format = "fallback" } or nil
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
