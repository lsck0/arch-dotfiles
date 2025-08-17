local ls = require("luasnip")
local s = ls.snippet
local i = ls.insert_node
local t = ls.text_node

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
