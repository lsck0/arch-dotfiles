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
                        Rule("$", "$", tex_ft)
                        -- don't pair if next char is alphanumeric
                            :with_pair(cond.not_after_regex("[%w]")),
                        Rule("\\(", "\\)", tex_ft),
                        Rule("\\[", "\\]", tex_ft),
                    })
                end,
            },

            {
                "github/copilot.vim",
                config = function()
                    vim.api.nvim_set_hl(0, "CopilotSuggestion", { fg = "#910367" })
                    vim.keymap.set("i", "<C-a>", "copilot#Accept('<CR>')", {
                        expr = true,
                        replace_keycodes = false
                    })
                    vim.g.copilot_no_tab_map = true
                end
            },

            {
                "L3MON4D3/LuaSnip",
                version = "v2.*",
                build = "make install_jsregexp"
            },

            { "onsails/lspkind.nvim" },

            -- compat layer for nvim-cmp sources without native blink equivalents
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
                ["<Tab>"] = { "select_next", "fallback" },
                ["<S-Tab>"] = { "select_prev", "fallback" },
                ["<C-b>"] = { "scroll_documentation_up", "fallback" },
                ["<C-f>"] = { "scroll_documentation_down", "fallback" },
            },

            completion = {
                list = { selection = { preselect = true, auto_insert = false } },
                documentation = { auto_show = true, auto_show_delay_ms = 200 },
                menu = {
                    winhighlight = "Normal:NormalFloat,FloatBorder:FloatBorder,Search:None,CursorLine:MyCursorLine",
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
                default = {
                    "lsp",
                    "path",
                    "snippets",
                    "buffer",
                    "commits",
                    "conventionalcommits",
                    "calc",
                },
                providers = {
                    commits = {
                        name = "commits",
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

            fuzzy = { implementation = "prefer_rust_with_warning" },
        },
        opts_extend = { "sources.default" },
        config = function(_, opts)
            vim.api.nvim_set_hl(0, "MyCursorLine", { link = "PmenuSel" })
            require("blink.cmp").setup(opts)
        end,
    },
}
