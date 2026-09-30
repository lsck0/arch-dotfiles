return {
    {
        "stevearc/oil.nvim", -- edit dirs as buffers
        cmd = { "Oil" },
        config = function()
            require("oil").setup()
        end
    },
}
