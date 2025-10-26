local ls = require("luasnip")
local s = ls.snippet
local i = ls.insert_node
local t = ls.text_node

local common_snippets = {
    s("banner", {
        t({ "", "" }),
        t({ "/*",
            " * ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────" }),
        t({ "", " * " }), i(1),
        t({ "",
            " * ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────",
            " */" }),
        t({ "", "" }),
    }),
    s("smallbanner", {
        t({ "", "" }),
        t({ "/*",
            " * ─────────────────────────────────────────────────────────" }),
        t({ "", " * " }), i(1),
        t({ "",
            " * ─────────────────────────────────────────────────────────",
            " */" }),
        t({ "", "" }),
    }),
}

ls.add_snippets("rust", {
    s("struct", {
        t("#[derive(Debug, Clone)]"),
        t("pub struct "),
        i(1, "Name"),
        t("{"),
        t("}"),
    }),
    s("enum", {
        t("#[derive(Debug, Clone)]"),
        t("pub enum "),
        i(1, "Name"),
        t("{"),
        t("}"),
    })
})

ls.add_snippets("c", vim.deepcopy(common_snippets))
ls.add_snippets("cpp", vim.deepcopy(common_snippets))
ls.add_snippets("h", vim.deepcopy(common_snippets))
ls.add_snippets("hpp", vim.deepcopy(common_snippets))
