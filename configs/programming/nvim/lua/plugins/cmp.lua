return {
    {
        "saghen/blink.cmp",
        version = "1.*",
        dependencies = {
            {
                "windwp/nvim-autopairs",
                opts = {
                    fast_wrap = {},
                    disable_filetype = { "TelescopePrompt", "vim" },
                },
                config = function(_, opts)
                    local npairs = require("nvim-autopairs")
                    npairs.setup(opts)

                    local Rule = require("nvim-autopairs.rule")
                    local cond = require("nvim-autopairs.conds")
                    local tex_ft = { "tex", "latex", "markdown" }
                    npairs.add_rules({
                        Rule("$", "$", tex_ft):with_pair(cond.not_after_regex("[%w]")),
                        Rule("\\(", "\\)", tex_ft),
                        Rule("\\[", "\\]", tex_ft),
                    })
                end,
            },

            {
                "L3MON4D3/LuaSnip",
                version = "v2.*",
                build = "make install_jsregexp",
                config = function()
                    local ls = require("luasnip")
                    ls.setup({ enable_autosnippets = true })
                    require("luasnip.loaders.from_lua").lazy_load({
                        paths = { vim.fn.stdpath("config") .. "/snippets" },
                    })
                    ls.filetype_extend("cpp", { "c" })
                    ls.filetype_extend("plaintex", { "tex" })
                    for _, ft in ipairs({ "typescript", "javascriptreact", "typescriptreact" }) do
                        ls.filetype_extend(ft, { "javascript" })
                    end
                end,
            },

            { "onsails/lspkind.nvim" },

            {
                "saghen/blink.compat",
                version = "2.*",
                opts = {},
                dependencies = {
                    "Dosx001/cmp-commit",
                    "davidsierradz/cmp-conventionalcommits",
                    "hrsh7th/cmp-calc",
                },
            },
        },
        opts = {
            snippets = { preset = "luasnip" },

            keymap = {
                preset = "none",
                ["<C-Space>"] = { "show", "show_documentation", "hide_documentation" },
                ["<C-e>"] = { "cancel", "fallback" },
                ["<CR>"] = { "accept", "fallback" },
                ["<Tab>"] = { "select_next", "snippet_forward", "fallback" },
                ["<S-Tab>"] = { "select_prev", "snippet_backward", "fallback" },
                ["<Down>"] = { "select_next", "fallback" },
                ["<Up>"] = { "select_prev", "fallback" },
                ["<C-b>"] = { "scroll_documentation_up", "fallback" },
                ["<C-f>"] = { "scroll_documentation_down", "fallback" },
            },

            signature = { enabled = true },

            completion = {
                list = { selection = { preselect = true, auto_insert = false } },
                documentation = { auto_show = true, auto_show_delay_ms = 200 },
                menu = {
                    draw = {
                        components = {
                            kind_icon = {
                                text = function(ctx)
                                    local kind = require("lspkind").symbolic(ctx.kind, { mode = "symbol" })
                                    return string.format("[%s]", kind)
                                end,
                            },
                        },
                    },
                },
            },

            sources = {
                default = { "lsp", "path", "snippets", "buffer", "calc" },
                -- cmp-commit lists the whole cwd recursively on every { [ *, which froze tex buffers
                per_filetype = {
                    gitcommit = { inherit_defaults = true, "commits", "conventionalcommits" },
                    tex = { inherit_defaults = true, "citations" },
                    plaintex = { inherit_defaults = true, "citations" },
                    markdown = { inherit_defaults = true, "citations" },
                },
                providers = {
                    citations = {
                        name = "Cite",
                        module = "lib.citation_source",
                    },
                    commits = {
                        name = "commit",
                        module = "blink.compat.source",
                    },
                    conventionalcommits = {
                        name = "conventionalcommits",
                        module = "blink.compat.source",
                    },
                    calc = {
                        name = "calc",
                        module = "blink.compat.source",
                    },
                },
            },
        },
    },
}
