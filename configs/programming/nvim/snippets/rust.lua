local ls = require("luasnip")
local s, i, t = ls.snippet, ls.insert_node, ls.text_node

return {
    s("struct", { t({ "#[derive(Debug, Clone)]", "pub struct " }), i(1, "Name"), t({ " {", "}" }) }),
    s("enum", { t({ "#[derive(Debug, Clone)]", "pub enum " }), i(1, "Name"), t({ " {", "}" }) }),
}
