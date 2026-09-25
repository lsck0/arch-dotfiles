local installed = {
    "asm",
    "bash",
    "c",
    "c_sharp",
    "clojure",
    "cmake",
    "comment",
    "cpp",
    "css",
    "diff",
    "dockerfile",
    "doxygen",
    "elixir",
    "gdshader",
    "git_rebase",
    "gitcommit",
    "gitignore",
    "go",
    "gomod",
    "gosum",
    "graphql",
    "haskell",
    "hcl",
    "heex",
    "html",
    "hyprlang",
    "java",
    "javascript",
    "latex",
    "bibtex",
    "jsdoc",
    "json",
    "kotlin",
    "lua",
    "luadoc",
    "make",
    "markdown",
    "markdown_inline",
    "nasm",
    "nix",
    "ocaml",
    "php",
    "printf",
    "prisma",
    "proto",
    "python",
    "query",
    "regex",
    "ruby",
    "rust",
    "scala",
    "scss",
    "sql",
    "svelte",
    "terraform",
    "toml",
    "tsx",
    "typescript",
    "vim",
    "vimdoc",
    "vue",
    "xml",
    "yaml",
    "zig",
}

return {
    {
        "nvim-treesitter/nvim-treesitter", -- syntax highlighting/parsing
        branch = "main",
        event = { "BufReadPost", "BufNewFile" }, -- load on first real buffer, before FileType highlight
        cmd = { "TSUpdate", "TSInstall" },
        build = ":TSUpdate",
        dependencies = {
            { "nvim-treesitter/nvim-treesitter-context" }, -- sticky function context
            { "IndianBoy42/tree-sitter-just" },            -- justfile syntax
        },
        config = function()
            local treesitter = require("nvim-treesitter")
            treesitter.setup({
                install_dir = vim.fn.stdpath("data") .. "/site",
            })

            local system_parsers = {
                nya = vim.fn.stdpath("data") .. "/site/parser/nya.so",
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
                    treesitter.install(installed)
                end,
            })
        end,
    },
}
