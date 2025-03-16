return {
    {
        "hrsh7th/nvim-cmp",
        dependencies = {
            {
                "github/copilot.vim",
                config = function()
                    vim.keymap.set("i", "<C-a>", "copilot#Accept('<CR>')", {
                        expr = true,
                        replace_keycodes = false
                    })
                    vim.g.copilot_no_tab_map = true
                end
            },

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
                "hrsh7th/cmp-nvim-lua",
                "hrsh7th/cmp-nvim-lsp",
                "hrsh7th/cmp-buffer",
                "hrsh7th/cmp-path",
                "hrsh7th/cmp-calc",
            },

            { "onsails/lspkind.nvim" },
        },
        config = function()
            local cmp = require("cmp")

            cmp.setup({
                sources = {
                    { name = "nvim_lsp" },
                    { name = "path" },
                    { name = "buffer" },
                    { name = 'calc' },
                    { name = 'render-markdown' },
                },
                mapping = cmp.mapping.preset.insert({
                    ["<C-Space>"] = cmp.mapping.complete(),
                    ["<C-e>"] = cmp.mapping.abort(),
                    ["<CR>"] = cmp.mapping.confirm({ select = true }),
                }),
                window = {
                    completion = {
                        winhighlight = "Normal:Pmenu,FloatBorder:Pmenu,Search:None",
                        col_offset = -3,
                        side_padding = 1,
                    },
                },
                performance = {
                    debounce = 200,
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
                            latex_symbols = "[TeX]",
                            nvim_lsp = "[LSP]",
                            path = "[Path]",
                        })[entry.source.name]

                        return vim_item
                    end,
                },
            })
        end,
    },
}
