local ls = require("luasnip")
local s, i, t = ls.snippet, ls.insert_node, ls.text_node

local M = {}

local RULE_WIDE = " " .. string.rep("-", 117)
local RULE_SMALL = " " .. string.rep("-", 57)

--- `banner` and `smallbanner` section comments in one comment syntax.
---@param open string first line of the comment block
---@param line string prefix of a rule line
---@param mid string prefix of the title line
---@param close string last line of the comment block
function M.create(open, line, mid, close)
    local function banner(trigger, rule)
        return s(trigger, {
            t({ "", open, line .. rule, mid }),
            i(1),
            t({ "", line .. rule, close, "" }),
        })
    end
    return { banner("banner", RULE_WIDE), banner("smallbanner", RULE_SMALL) }
end

return M
