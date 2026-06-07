vim.filetype.add({
    extension = {
        hlsl = "hlsl",
        fx = "hlsl",
        shader = "hlsl",
        json = "avsc",
    },
    pattern = { [".*/hyprland/.*%.conf"] = "hyprlang", },
})
