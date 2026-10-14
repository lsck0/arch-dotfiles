vim.filetype.add({
    extension = {
        avsc = "json",
        con = "c",
        fx = "hlsl",
        hlsl = "hlsl",
        shader = "hlsl",
        nya = "nya",
        nuon = "nu",
    },
    pattern = {
        [".*/hyprland/.*%.conf"] = "hyprlang",
        -- compose files get the docker compose LSP on top of yamlls, treesitter still reads the yaml part
        [".*/compose%.ya?ml"] = "yaml.docker-compose",
        [".*/compose%.[^/]+%.ya?ml"] = "yaml.docker-compose", -- compose.override.yaml, ...
        [".*/docker%-compose%.ya?ml"] = "yaml.docker-compose",
        [".*/docker%-compose%.[^/]+%.ya?ml"] = "yaml.docker-compose",
    },
})
