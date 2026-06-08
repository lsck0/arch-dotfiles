vim.filetype.add({
    extension = {
        avsc = "json",
        con = "c",
        fx = "hlsl",
        hlsl = "hlsl",
        shader = "hlsl",
    },
    pattern = { [".*/hyprland/.*%.conf"] = "hyprlang", },
})
