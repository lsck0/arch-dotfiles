return {
    {
        "nvim-treesitter/nvim-treesitter",
        branch = "main",
        lazy = false,
        build = ":TSUpdate",
        dependencies = {
            { "nvim-treesitter/nvim-treesitter-context" },
            { "IndianBoy42/tree-sitter-just" },
        },
        config = function()
            local treesitter = require("nvim-treesitter")
            local languages = {
                "bash",
                "c",
                "cmake",
                "cpp",
                "css",
                "dockerfile",
                "gdshader",
                "haskell",
                "html",
                "hyprlang",
                "java",
                "javascript",
                "json",
                "lua",
                "luadoc",
                "make",
                "markdown",
                "markdown_inline",
                "ocaml",
                "printf",
                "python",
                "query",
                "rust",
                "scss",
                "sql",
                "toml",
                "typescript",
                "vim",
                "vimdoc",
                "yaml",
            }

            treesitter.setup({
                install_dir = vim.fn.stdpath("data") .. "/site",
            })

            local system_parsers = {
                lua = "/usr/lib/libtree-sitter-lua.so",
                markdown = "/usr/lib/libtree-sitter-markdown.so",
                markdown_inline = "/usr/lib/libtree-sitter-markdown-inline.so",
                query = "/usr/lib/libtree-sitter-query.so",
                vim = "/usr/lib/libtree-sitter-vim.so",
                vimdoc = "/usr/lib/libtree-sitter-vimdoc.so",
            }
            for lang, path in pairs(system_parsers) do
                if vim.uv.fs_stat(path) then
                    vim.treesitter.language.add(lang, { path = path })
                end
            end

            vim.api.nvim_create_autocmd("VimEnter", {
                group = vim.api.nvim_create_augroup("TreesitterAutoInstall", { clear = true }),
                once = true,
                callback = function()
                    treesitter.install(languages)
                end,
            })
        end,
    },
}
