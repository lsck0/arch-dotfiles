vim.filetype.add({
    extension = {
        avsc = "json",
        con = "c",
        fx = "hlsl",
        hlsl = "hlsl",
        shader = "hlsl",
        nya = "nya",
    },
    pattern = { [".*/hyprland/.*%.conf"] = "hyprlang", },
})
