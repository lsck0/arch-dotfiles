local installed = {
    "asm", "bash", "c", "c_sharp", "clojure", "cmake", "comment", "cpp", "css",
    "diff", "dockerfile", "doxygen", "elixir", "gdscript", "gdshader", "git_rebase",
    "gitcommit", "gitignore", "go", "gomod", "gosum", "glsl", "graphql", "haskell",
    "hcl", "heex", "html", "hyprlang", "java", "javascript", "latex", "bibtex",
    "jsdoc", "json", "just", "kotlin", "lua", "luadoc", "make", "markdown",
    "markdown_inline", "nasm", "nix", "ocaml", "php", "printf", "prisma", "proto",
    "python", "query", "regex", "ruby", "rust", "scala", "scss", "sql", "svelte",
    "terraform", "toml", "tsx", "typescript", "typst", "vim", "vimdoc", "vue",
    "wgsl", "xml", "yaml", "zig",
}

return {
    {
        "nvim-treesitter/nvim-treesitter", -- syntax highlighting/parsing
        branch = "main",
        event = { "BufReadPost", "BufNewFile" }, -- before FileType highlight
        cmd = { "TSUpdate", "TSInstall", "TSInstallSync" },
        build = ":TSUpdate",
        dependencies = {
            { "nvim-treesitter/nvim-treesitter-context" }, -- sticky function context
        },
        config = function()
            local treesitter = require("nvim-treesitter")
            -- install_dir defaults to stdpath("data")/site, which is already on the runtimepath
            treesitter.setup()

            -- blocking parser install for a headless/manual run; startup installs async below
            vim.api.nvim_create_user_command("TSInstallSync", function()
                treesitter.install(installed):wait()
            end, { desc = "Install configured parsers and wait" })

            -- lazy-loaded on a later buffer, VimEnter has already fired then
            if vim.v.vim_did_enter == 1 then
                treesitter.install(installed)
            else
                vim.api.nvim_create_autocmd("VimEnter", {
                    group = vim.api.nvim_create_augroup("TreesitterAutoInstall", { clear = true }),
                    once = true,
                    callback = function()
                        treesitter.install(installed)
                    end,
                })
            end
        end,
    },
}
