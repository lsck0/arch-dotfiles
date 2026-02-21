vim.filetype.add({
    extension = {
        hlsl = "hlsl",
        fx = "hlsl",
        shader = "hlsl",
    },
})

vim.filetype.add({
    pattern = { [".*/hyprland/.*%.conf"] = "hyprlang" },
})
