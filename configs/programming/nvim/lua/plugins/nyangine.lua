-- nyangine's own plugin (its checkout's tooling/editors/nvim) owns .nya: the filetype, the tree-sitter grammar and
-- queries, formatting through `./build format` (conform's `nyangine` formatter), lua_ls inside a checkout and `:Nya`;
-- its paths are a contract with the nyangine session (l-project-agents). Without the checkout nothing loads.
local dir = vim.fn.expand("~/projects/nyangine/tooling/editors/nvim")

return {
    {
        dir = dir,
        name = "nyangine",
        cond = vim.uv.fs_stat(dir) ~= nil,
        lazy = false,
    },
}
