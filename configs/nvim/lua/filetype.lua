vim.filetype.add({
    extension = {
        hlsl = "hlsl",
        fx = "hlsl",
        shader = "hlsl",
        json = "avsc",
    },
})

vim.filetype.add({
    pattern = { [".*/hyprland/.*%.conf"] = "hyprlang" },
})
