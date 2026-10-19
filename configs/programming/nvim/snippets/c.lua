local ls = require("luasnip")
local s, i, t = ls.snippet, ls.insert_node, ls.text_node

local snippets = require("lib.snippet_banner").create("/*", " *", " * ", " */")

vim.list_extend(snippets, {
    s("sec", {
        t({ "/*", " * -----------------------------------------------------------------------------", " * " }),
        i(1, "SECTION"),
        t({ "", " * -----------------------------------------------------------------------------", " */", "" }),
    }),
    s("const", {
        t("// "),
        i(1, "why: measured against, trades off, breaks above/below"),
        t({ "", "#define " }),
        i(2, "NAME"),
        t(" "),
        i(3, "value"),
    }),
    s("assert", { t("assert("), i(1, "cond"), t(");") }),
    s("brief", { t("/** @brief "), i(1, "summary"), t(" */") }),
    s("param", { t("@param "), i(1, "name"), t(" "), i(2, "desc") }),
    s("return", { t("@return "), i(1, "desc") }),
    s("doc", {
        t({ "/**", " * @brief " }),
        i(1, "summary"),
        t({ "", " *", " * @param " }),
        i(2, "name"),
        t(" "),
        i(3, "desc"),
        t({ "", " * @return " }),
        i(4, "desc"),
        t({ "", " */" }),
    }),
})

return snippets
