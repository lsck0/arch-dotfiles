local ls = require("luasnip")
local s = ls.snippet
local i = ls.insert_node
local t = ls.text_node


--
-- ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
--   BANNER SNIPPETS
-- ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
--


local function make_banner_snippets(open, line, mid, close)
    return {
        s("banner", {
            t({ "", "" }),
            t({ open,
                line ..
                " ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────" }),
            t({ "", mid }), i(1),
            t({ "",
                line ..
                " ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────",
                close }),
            t({ "", "" }),
        }),
        s("smallbanner", {
            t({ "", "" }),
            t({ open,
                line .. " ─────────────────────────────────────────────────────────" }),
            t({ "", mid }), i(1),
            t({ "",
                line .. " ─────────────────────────────────────────────────────────",
                close }),
            t({ "", "" }),
        }),
    }
end

local c_style = make_banner_snippets("/*", " *", " * ", " */")
local hash_style = make_banner_snippets("#", "#", "# ", "#")
local tex_style = make_banner_snippets("%", "%", "% ", "%")
local lua_style = make_banner_snippets("--", "--", "-- ", "--")

ls.add_snippets("c", vim.deepcopy(c_style))
ls.add_snippets("cpp", vim.deepcopy(c_style))
ls.add_snippets("h", vim.deepcopy(c_style))
ls.add_snippets("hpp", vim.deepcopy(c_style))
ls.add_snippets("javascript", vim.deepcopy(c_style))
ls.add_snippets("typescript", vim.deepcopy(c_style))
ls.add_snippets("javascriptreact", vim.deepcopy(c_style))
ls.add_snippets("typescriptreact", vim.deepcopy(c_style))
ls.add_snippets("python", vim.deepcopy(hash_style))
ls.add_snippets("tex", vim.deepcopy(tex_style))
ls.add_snippets("plaintex", vim.deepcopy(tex_style))
ls.add_snippets("lua", vim.deepcopy(lua_style))


--
-- ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
-- RUST SNIPPETS
-- ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
--


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
