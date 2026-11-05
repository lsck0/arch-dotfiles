vim.filetype.add({
    filename = { PKGBUILD = "pkgbuild" },
    extension = {
        avsc = "json",
        con = "c",
        fx = "hlsl",
        hlsl = "hlsl",
        -- nvim guesses lifelines for an .ll without a leading comment or target line
        ll = "llvm",
        shader = "hlsl",
        nya = "nya",
        nuon = "nu",
    },
    pattern = {
        [".*/hyprland/.*%.conf"] = "hyprlang",
        [".*/compose%.ya?ml"] = "yaml.docker-compose",
        [".*/compose%.[^/]+%.ya?ml"] = "yaml.docker-compose",
        [".*/docker%-compose%.ya?ml"] = "yaml.docker-compose",
        [".*/docker%-compose%.[^/]+%.ya?ml"] = "yaml.docker-compose",
    },
})

vim.treesitter.language.register("bash", "pkgbuild")
