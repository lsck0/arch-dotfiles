local installed = {
    "asm-lsp",
    "bash-language-server",
    "bibtex-tidy",
    "clangd",
    "cobol-language-support",
    "codelldb",
    "css-lsp",
    "cssmodules-language-server",
    "debugpy",
    "docker-compose-language-service",
    "dockerfile-language-server",
    "emmet-language-server",
    "eslint-lsp",
    "glsl_analyzer",
    "gopls",
    "haskell-language-server",
    "hlint",
    "html-lsp",
    "hyprls",
    "java-debug-adapter",
    "java-test",
    "jdtls",
    "jinja-lsp",
    "js-debug-adapter",
    "json-lsp",
    -- kulala-fmt is vendored, see conform below
    "latexindent",
    "lean-language-server",
    "lemminx",
    "lua-language-server",
    "nil",
    "ormolu",
    "prettierd",
    "pyright",
    "ruff", -- python lint/format LSP, pyright keeps types
    "rust-analyzer",
    "slang-server",
    "sqruff", -- sqlls is unmaintained and crashes on load
    "stylua",
    "shfmt",
    "gofumpt",
    "goimports",
    "tailwindcss-language-server",
    "taplo",
    "terraform-ls",
    "texlab",
    "tinymist", -- typst LSP
    "tree-sitter-cli",
    "typescript-language-server",
    "typos-lsp",
    "vim-language-server",
    "wgsl-analyzer", -- mason package hyphenated, lspconfig server is wgsl_analyzer
    "yaml-language-server",
    "zls",
    "clojure-lsp",
    "elixir-ls",
    "graphql-language-service-cli",
    "intelephense",
    "kotlin-language-server",
    "marksman",
    "omnisharp",
    "ruby-lsp",
    "svelte-language-server",
    "vue-language-server",
    -- formatters
    "cljfmt",
    "csharpier",
    "ktlint",
    "php-cs-fixer",
    "rubocop",
    "sql-formatter",
}

return {
    {
        "folke/lazydev.nvim", -- Lua LSP for nvim config
        ft = "lua",
        opts = {
            library = {
                { path = "${3rd}/luv/library", words = { "vim%.uv" } },
            },
        },
    },
    -- per-language plugins live in lua/languages/ (jai.vim, vimtex, crates, lean)

    {
        "mason-org/mason.nvim",                              -- LSP/tool installer
        -- automatic_enable walks every installed server (~200ms), so wait for a real buffer;
        -- BufReadPre runs before FileType, so the first file still attaches
        event = { "BufReadPre", "BufNewFile" },
        cmd = {
            "Mason", "MasonInstall", "MasonUninstall", "MasonUpdate", "MasonLog",
            "MasonToolsInstall", "MasonToolsUpdate",
            "LspInfo", "LspLog", "LspStart", "LspStop", "LspRestart",
        },
        dependencies = {
            { "neovim/nvim-lspconfig" },                     -- LSP server configs
            { "mason-org/mason-lspconfig.nvim" },            -- mason lspconfig bridge
            { "WhoIsSethDaniel/mason-tool-installer.nvim" }, -- auto-install LSP tools
            { "marilari88/twoslash-queries.nvim" },          -- inline TS type hints
            {
                "ivanjermakov/troublesum.nvim",              -- diagnostic count summary
                config = function()
                    require("troublesum").setup()
                end
            },
            {
                "Sebastian-Nielsen/better-type-hover", -- improved hover popup
                config = function()
                    require("better-type-hover").setup()
                end,
            },
            {
                "dmmulroy/ts-error-translator.nvim", -- readable TS errors
                config = function()
                    require("ts-error-translator").setup()
                end
            },
        },
        config = function()
            vim.diagnostic.config({
                severity_sort = true,
                update_in_insert = false,
                underline = true,
                virtual_text = {
                    prefix = "●",
                    spacing = 2,
                    source = "if_many",
                },
                float = {
                    border = "rounded",
                    source = "if_many",
                    header = "",
                },
                signs = {
                    text = {
                        [vim.diagnostic.severity.ERROR] = vim.fn.nr2char(0xea87), -- nf-cod-error
                        [vim.diagnostic.severity.WARN]  = vim.fn.nr2char(0xea6c), -- nf-cod-warning
                        [vim.diagnostic.severity.INFO]  = vim.fn.nr2char(0xea74), -- nf-cod-info
                        [vim.diagnostic.severity.HINT]  = vim.fn.nr2char(0xea61), -- nf-cod-lightbulb
                    },
                },
            })

            require("mason").setup()
            require("mason-tool-installer").setup({
                ensure_installed = installed,
                -- installs missing tools on first launch; auto_update stays off so upgrades
                -- remain in scripts/system-update.sh, not on every startup
                run_on_start = true,
            })
            vim.lsp.config("clangd", {
                cmd = {
                    "clangd",
                    "--offset-encoding=utf-16",
                    "--background-index",
                },
            })

            local cobol_jar = vim.fn.stdpath("data")
                .. "/mason/packages/cobol-language-support/extension/server/jar/server.jar"
            if vim.uv.fs_stat(cobol_jar) then
                vim.lsp.config("cobol_ls", { cmd = { "java", "-jar", cobol_jar } })
                vim.lsp.enable("cobol_ls")
            end

            -- kani projects need these cfgs + nightly, plain rust must not get them
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
                -- per client root, so kani and plain crates can share one nvim
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
                    }
                }
            })

            -- tailwindcss only where class attributes exist
            vim.lsp.config("tailwindcss", {
                filetypes = {
                    "html", "css", "scss", "less", "javascript", "javascriptreact",
                    "typescript", "typescriptreact", "vue", "svelte",
                },
            })

            -- root at the typos config, else its allowlist is ignored
            vim.lsp.config("typos_lsp", {
                root_markers = { ".typos.toml", "_typos.toml", "typos.toml", ".git" },
                -- fallback config, a project .typos.toml overrides it
                init_options = { config = vim.fn.expand("~/.config/typos/typos.toml") },
            })

            -- vue_ls forwards script blocks to ts_ls, which needs the vue plugin for that
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

            -- system JDK (mise may pin an older java on PATH); java-debug bundle enables dap
            vim.lsp.config("jdtls", {
                cmd = { "jdtls", "--java-executable", "/usr/lib/jvm/default/bin/java" },
                init_options = {
                    bundles = vim.fn.glob(vim.fn.stdpath("data")
                        .. "/mason/packages/java-debug-adapter/extension/server/com.microsoft.java.debug.plugin-*.jar", true, true),
                },
            })

            -- jupytext buffers: drop undefined-var noise for ipython builtins
            local ipython_builtins = {
                display = true, get_ipython = true, In = true, Out = true,
                exit = true, quit = true,
            }
            -- project venv, so pyright sees poetry-installed packages
            local function project_python(root)
                -- a json-null rootPath is vim.NIL, which is truthy
                if type(root) ~= "string" or root == "" then return nil end
                local venv = vim.env.VIRTUAL_ENV
                if venv and vim.fn.executable(venv .. "/bin/python") == 1 then
                    return venv .. "/bin/python"
                end
                if vim.fn.executable(root .. "/.venv/bin/python") == 1 then
                    return root .. "/.venv/bin/python"
                end
                if vim.fn.filereadable(root .. "/pyproject.toml") == 1
                    and vim.fn.executable("poetry") == 1 then
                    -- timeout so a slow poetry cannot block LSP init
                    local out = vim.trim(vim.fn.system({ "timeout", "2", "poetry", "-C", root, "env", "info", "-e" }))
                    if vim.v.shell_error == 0 and out ~= "" then return out end
                end
            end

            local function drop_ipython_noise(buf, diagnostics)
                if not vim.b[buf].is_jupytext then return diagnostics end
                return vim.tbl_filter(function(d)
                    local name = d.code == "reportUndefinedVariable"
                        and d.message:match('"([%w_]+)"')
                    return not (name and ipython_builtins[name])
                end, diagnostics)
            end

            local publish = vim.lsp.handlers["textDocument/publishDiagnostics"]
            local pull = vim.lsp.handlers["textDocument/diagnostic"]
            vim.lsp.config("pyright", {
                before_init = function(params, config)
                    local root = params.rootPath
                        or (params.rootUri and vim.uri_to_fname(params.rootUri))
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
                    -- pyright pulls diagnostics (textDocument/diagnostic), filter those too
                    ["textDocument/diagnostic"] = function(err, result, ctx)
                        if result and result.items then
                            result.items = drop_ipython_noise(ctx.bufnr, result.items)
                        end
                        return pull(err, result, ctx)
                    end,
                },
            })

            -- texlab handles completion + chktex lint; vimtex owns build/preview
            vim.lsp.config("texlab", {
                settings = {
                    texlab = {
                        build = { onSave = false, forwardSearchAfter = false },
                        chktex = { onOpenAndSave = false, onEdit = false },
                        latexindent = { modifyLineBreaks = false },
                        diagnosticsDelay = 300,
                    },
                },
            })

            vim.lsp.enable("clangd")
            -- godot ships a GDScript server over TCP :6005, no mason package
            vim.lsp.enable("gdscript")
            vim.lsp.enable("pyright")
            vim.lsp.enable("rust_analyzer")
            vim.lsp.enable("tailwindcss")
            vim.lsp.enable("ts_ls")

            require("mason-lspconfig").setup({
                automatic_enable = {
                    exclude = {
                        "clangd",
                        "cobol_ls",
                        "pyright",
                        "rust_analyzer",
                        "tailwindcss",
                        "ts_ls",
                        -- crash on start: no elixir runtime, JDK crash, bundler perms
                        "elixirls",
                        "kotlin_language_server",
                        "ruby_lsp",
                    }
                }
            })
        end,
    },

    {
        "stevearc/conform.nvim", -- code formatting
        config = function()
            require("conform").formatters.sortderives = {
                inherit = false,
                command = vim.fn.expand("~/.local/bin/sort-derives-stdout"),
                stdin = true,
            }
            -- l-style shell: 4-space indent, indented cases, binary ops lead the line
            require("conform").formatters.shfmt = {
                prepend_args = { "-i", "4", "-ci", "-bn" },
            }
            -- vendored kulala-fmt, not from mason
            require("conform").formatters["kulala-fmt"] = { command = vim.fn.stdpath("config") .. "/vendor/kulala-fmt/kulala-fmt" }

            require("conform").setup({
                formatters_by_ft = {
                    bib = { "bibtex-tidy" },
                    css = { "prettier" },
                    haskell = { "ormolu" },
                    html = { "prettier" },
                    http = { "kulala-fmt" },
                    javascript = { "prettier" },
                    plaintex = { "latexindent" },
                    python = { "ruff_organize_imports", "ruff_format" }, -- width from configs/formatting/ruff.toml
                    rest = { "kulala-fmt" },
                    -- leptosfmt only in leptos projects, else it errors on plain Rust
                    rust = function(bufnr)
                        local fmts = { "rustfmt", "sortderives" }
                        local root = vim.fs.root(bufnr, { "Cargo.toml" })
                        local f = root and io.open(root .. "/Cargo.toml")
                        if f then
                            if f:read("*a"):find("leptos") then table.insert(fmts, "leptosfmt") end
                            f:close()
                        end
                        return fmts
                    end,
                    scss = { "prettier" },
                    tex = { "latexindent" },
                    typst = { "typstyle" },
                    typescript = { "prettier" },
                    typescriptreact = { "prettier" },
                    javascriptreact = { "prettier" },
                    lua = { "stylua" },
                    json = { "prettier" },
                    jsonc = { "prettier" },
                    yaml = { "prettier" },
                    markdown = { "prettier" },
                    sh = { "shfmt" },
                    bash = { "shfmt" },
                    go = { "goimports", "gofumpt" },
                    nix = { "nixfmt" },
                    ruby = { "rubocop" },
                    php = { "php_cs_fixer" },
                    cs = { "csharpier" },
                    kotlin = { "ktlint" },
                    vue = { "prettier" },
                    svelte = { "prettier" },
                    graphql = { "prettier" },
                    clojure = { "cljfmt" },
                    elixir = { "mix" },
                    sql = { "sql_formatter" },
                },
                -- toggle with :FormatToggle (g:) or per-buffer (b:disable_autoformat)
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
    }
}
