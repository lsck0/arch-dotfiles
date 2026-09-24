local installed = {
    "asm-lsp",
    "bash-language-server",
    "bibtex-tidy",
    "black",
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
    "gopls",
    "haskell-language-server",
    "hlint",
    "html-lsp",
    "hyprls",
    "isort",
    "java-debug-adapter",
    "java-test",
    "jdtls",
    "jinja-lsp",
    "js-debug-adapter",
    "json-lsp",
    "kulala-fmt",
    "latexindent",
    "lean-language-server",
    "lemminx",
    "lua-language-server",
    "nil",
    "ormolu",
    "prettierd",
    "pyright",
    "rust-analyzer",
    "slang-server",
    "sqlls",
    "stylua",
    "shfmt",
    "gofumpt",
    "goimports",
    "tailwindcss-language-server",
    "taplo",
    "terraform-ls",
    "texlab",
    "tree-sitter-cli",
    "typescript-language-server",
    "typos-lsp",
    "vim-language-server",
    "yaml-language-server",
    "zls",
    -- broader popular-language coverage (LSPs)
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
    -- their formatters
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
                -- upgrades run from scripts/system-update.sh, not on every startup
                run_on_start = false,
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

            -- kani projects need these cfgs + nightly; plain Rust must NOT get
            local function rust_extra_env()
                local root = vim.fs.root(vim.fn.getcwd(), { "Cargo.toml" }) or vim.fn.getcwd()
                local f = io.open(root .. "/Cargo.toml")
                if f then
                    local uses_kani = f:read("*a"):find("kani") ~= nil
                    f:close()
                    if uses_kani then
                        return { RUSTFLAGS = "--cfg kani_ra --cfg kani", RUSTUP_TOOLCHAIN = "nightly" }
                    end
                end
                return vim.empty_dict()
            end
            local rust_env = rust_extra_env()

            vim.lsp.config("rust_analyzer", {
                settings = {
                    ["rust-analyzer"] = {
                        cargo = { allFeatures = true, extraEnv = rust_env },
                        check = { command = "clippy", extraEnv = rust_env },
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


            vim.lsp.config("ts_ls", {
                on_attach = function(client, bufnr)
                    require("twoslash-queries").attach(client, bufnr)
                end,
            })

            -- system JDK (mise may pin an older java on PATH); java-debug bundle enables dap
            vim.lsp.config("jdtls", {
                cmd = { "jdtls", "--java-executable", "/usr/lib/jvm/default/bin/java" },
                init_options = {
                    bundles = vim.fn.glob(vim.fn.stdpath("data")
                        .. "/mason/packages/java-debug-adapter/extension/server/com.microsoft.java.debug.plugin-*.jar", true, true),
                },
            })

            -- In jupytext notebook buffers, drop pyright undefined-var noise for IPython builtins.
            local ipython_builtins = {
                display = true, get_ipython = true, In = true, Out = true,
                exit = true, quit = true,
            }
            -- point pyright at the project's virtualenv so poetry-installed
            local function project_python(root)
                if not root then return nil end
                local venv = vim.env.VIRTUAL_ENV
                if venv and vim.fn.executable(venv .. "/bin/python") == 1 then
                    return venv .. "/bin/python"
                end
                if vim.fn.executable(root .. "/.venv/bin/python") == 1 then
                    return root .. "/.venv/bin/python"
                end
                if vim.fn.filereadable(root .. "/pyproject.toml") == 1
                    and vim.fn.executable("poetry") == 1 then
                    local out = vim.trim(vim.fn.system({ "poetry", "-C", root, "env", "info", "-e" }))
                    if vim.v.shell_error == 0 and out ~= "" then return out end
                end
            end

            local publish = vim.lsp.handlers["textDocument/publishDiagnostics"]
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
                        local buf = vim.uri_to_bufnr(result.uri)
                        if vim.b[buf].is_jupytext then
                            result.diagnostics = vim.tbl_filter(function(d)
                                local name = d.code == "reportUndefinedVariable"
                                    and d.message:match('"([%w_]+)"')
                                return not (name and ipython_builtins[name])
                            end, result.diagnostics)
                        end
                        return publish(err, result, ctx)
                    end,
                },
            })

            vim.lsp.enable("clangd")
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
                    }
                }
            })
        end,
    },

    {
        "antosha417/nvim-lsp-file-operations", -- LSP-aware file ops
        dependencies = {
            "nvim-lua/plenary.nvim",           -- Lua utility library
            "nvim-neo-tree/neo-tree.nvim",     -- sidebar file tree
        },
        config = function()
            require("lsp-file-operations").setup()
        end,
    },

    {
        "stevearc/conform.nvim", -- code formatting
        config = function()
            require("conform").formatters.sortderives = {
                inherit = false,
                command = "/usr/local/bin/sort-derives-stdout",
                stdin = true,
            }
            -- l-style shell: 4-space indent, indent switch cases, binary ops at
            require("conform").formatters.shfmt = {
                prepend_args = { "-i", "4", "-ci", "-bn" },
            }
            -- l-style width for python (black defaults to 88)
            require("conform").formatters.black = { prepend_args = { "--line-length", "120" } }
            require("conform").formatters.isort = { prepend_args = { "--line-length", "120", "--profile", "black" } }

            require("conform").setup({
                formatters_by_ft = {
                    bib = { "bibtex-tidy" },
                    css = { "prettier" },
                    haskell = { "ormolu" },
                    html = { "prettier" },
                    http = { "kulala-fmt" },
                    javascript = { "prettier" },
                    latex = { "latexindent" },
                    python = { "isort", "black" },
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
                    vim.b.disable_autoformat = not vim.b.disable_autoformat -- buffer-local
                else
                    vim.g.disable_autoformat = not vim.g.disable_autoformat -- global
                end
                vim.notify("autoformat " .. ((vim.g.disable_autoformat or vim.b.disable_autoformat) and "off" or "on"))
            end, { bang = true, desc = "Toggle format-on-save (! = buffer only)" })
        end,
    }
}
