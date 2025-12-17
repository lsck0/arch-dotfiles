return {
    {
        "hrsh7th/nvim-cmp",
        dependencies = {
            {
                "windwp/nvim-autopairs",
                opts = {
                    fast_wrap = {},
                    disable_filetype = { "TelescopePrompt", "vim" },
                },
                config = function(_, opts)
                    require("nvim-autopairs").setup(opts)
                    local cmp_autopairs = require "nvim-autopairs.completion.cmp"
                    require("cmp").event:on("confirm_done", cmp_autopairs.on_confirm_done())
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

            {
                "Dosx001/cmp-commit",
                "davidsierradz/cmp-conventionalcommits",
                "hrsh7th/cmp-buffer",
                "hrsh7th/cmp-calc",
                "hrsh7th/cmp-nvim-lsp",
                "hrsh7th/cmp-nvim-lua",
                "hrsh7th/cmp-path",
                "saadparwaiz1/cmp_luasnip",
            },
        },
        config = function()
            vim.api.nvim_set_hl(0, "MyCursorLine", { fg = "#6c6f93" })

            local cmp = require("cmp")

            cmp.setup({
                preselect = cmp.PreselectMode.None,
                sources = {
                    { name = "luasnip" },
                    { name = "nvim_lsp" },
                    { name = "path" },
                    { name = "commits" },
                    { name = "conventionalcommits" },
                    { name = "calc" },
                    { name = "render-markdown" },
                    { name = "buffer" },
                },
                mapping = cmp.mapping.preset.insert({
                    ["<C-Space>"] = cmp.mapping.complete(),
                    ["<C-e>"] = cmp.mapping.abort(),
                    ["<CR>"] = cmp.mapping.confirm({ select = true }),
                }),
                window = {
                    completion = {
                        winhighlight = "Normal:Pmenu,FloatBorder:Pmenu,Search:None,CursorLine:MyCursorLine",
                        col_offset = -3,
                        side_padding = 1,
                    },
                },
                performance = {
                    debounce = 100,
                },
                formatting = {
                    fields = { "kind", "abbr", "menu" },
                    format = function(entry, vim_item)
                        local kind = require("lspkind").cmp_format({
                            mode = 'symbol',
                            maxwidth = 30,
                            ellipsis_char = '...',
                            show_labelDetails = true,
                        })(entry, vim_item)

                        vim_item.kind = string.format("[%s]", kind.kind)

                        vim_item.menu = ({
                            buffer = "[Buf]",
                            calc = "[Calc]",
                            commits = "[Commit]",
                            conventionalcommits = "[CC]",
                            latex_symbols = "[TeX]",
                            luasnip = "[Snip]",
                            nvim_lsp = "[LSP]",
                            path = "[Path]",
                            render_markdown = "[Markdown]",
                        })[entry.source.name]

                        return vim_item
                    end,
                },
            })
        end,
    },
}
