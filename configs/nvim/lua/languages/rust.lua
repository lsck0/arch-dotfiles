-- Rust language plugins: crates.nvim, rustaceanvim, and shared LSP/format infra.
return {
    {
        "saecki/crates.nvim", -- Cargo.toml crate info + versions
        ft = "toml",
        config = function() require("crates").setup({}) end,
    },
}
