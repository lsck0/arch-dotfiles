local ls = require("luasnip")
local s, sn, i, t, f, d = ls.snippet, ls.snippet_node, ls.insert_node, ls.text_node, ls.function_node, ls.dynamic_node
local fmta = require("luasnip.extras.fmt").fmta
local rep = require("luasnip.extras").rep
local line_begin = require("luasnip.extras.expand_conditions").line_begin

-- pcall: vimtex may not be loaded yet
local function in_math()
    local ok, res = pcall(vim.fn["vimtex#syntax#in_mathzone"])
    return ok and res == 1
end
local function not_math()
    return not in_math()
end
local function math_not_command(line_to_cursor, trigger)
    return in_math() and not line_to_cursor:sub(1, -#trigger - 1):match("\\%a*$")
end

local function cap(n)
    return f(function(_, snip)
        return snip.captures[n]
    end)
end

-- Header.sty's autolabels option derives the label from the title, so a written one would be defined twice.
local function autolabels()
    local main = vim.fs.find("main.tex", { path = vim.fn.expand("%:p:h"), upward = true })[1]
    local fd = main and io.open(main, "r")
    if not fd then
        return false
    end
    local text = fd:read("*a")
    fd:close()
    local options = text:match("\\usepackage%[([^%]]*)%]%s*{header}")
    return options ~= nil and options:find("autolabels", 1, true) ~= nil
end

local TRANSLIT = {
    a = "áàâäåãÁÀÂÄÅ",
    c = "çćčÇČ",
    d = "ďĎ",
    e = "éèêëěÉÈÊ",
    i = "íìîïÍ",
    l = "łŁ",
    n = "ñńň",
    o = "óòôöõøőÓÖØ",
    r = "řŘ",
    s = "śšŚŠ",
    ss = "ß",
    t = "ť",
    u = "úùûüůűÚÜ",
    y = "ý",
    z = "žźżŽ",
}

-- The slug header.sty's autolabels makes: commands drop to their argument, accents to the base letter.
local function slug(title)
    title = title:gsub("[$]", ""):gsub("\\%a+%*?", " ")
    for base, chars in pairs(TRANSLIT) do
        for _, char in ipairs(vim.fn.split(chars, "\\zs")) do
            title = title:gsub(char, base)
        end
    end
    return (title:lower():gsub("[^%w]+", "-"):gsub("^%-+", ""):gsub("%-+$", ""))
end

-- A cleveref-namespaced label: the kind written out, then a kebab-case slug of the title.
local function label(kind)
    return function(args)
        if autolabels() then
            return sn(nil, t(""))
        end
        return sn(nil, { t("\\label{" .. kind .. ":"), i(1, slug(args[1][1])), t({ "}", "    " }) })
    end
end

local function statement(trigger, env)
    return s({ trig = trigger, desc = env }, {
        t("\\begin{" .. env .. "}["),
        i(1, "title"),
        t({ "]", "    " }),
        d(2, label(env), { 1 }),
        i(0),
        t({ "", "\\end{" .. env .. "}" }),
    }, { condition = line_begin })
end

-- The statement with its proof as the last block inside it.
local function proved(trigger, env)
    return s({ trig = trigger, desc = env .. " with proof" }, {
        t("\\begin{" .. env .. "}["),
        i(1, "title"),
        t({ "]", "    " }),
        d(2, label(env), { 1 }),
        i(3),
        t({ "", "", "    \\begin{proof}", "        " }),
        i(0),
        t({ "", "    \\end{proof}", "\\end{" .. env .. "}" }),
    }, { condition = line_begin })
end

local snippets = require("lib.snippet_banner").create("%", "%", "% ", "%")

vim.list_extend(snippets, {
    s("sec", fmta("\\section{<>}<>", { i(1), i(0) })),
    s("ssec", fmta("\\subsection{<>}<>", { i(1), i(0) })),
    s("sssec", fmta("\\subsubsection{<>}<>", { i(1), i(0) })),
    s("par", fmta("\\paragraph{<>}<>", { i(1), i(0) })),

    statement("def", "definition"),
    proved("thm", "theorem"),
    proved("lem", "lemma"),
    proved("prop", "proposition"),
    proved("cor", "corollary"),
    statement("rem", "remark"),
    statement("ex", "example"),
    statement("ax", "axiom"),
    statement("conj", "conjecture"),
    s(
        { trig = "prf", desc = "proof" },
        fmta(
            [[
        \begin{proof}
            <>
        \end{proof}
    ]],
            { i(0) }
        ),
        { condition = line_begin }
    ),
    s({ trig = "cref", desc = "cleveref" }, fmta("\\cref{<>}", { i(1) })),
    s({ trig = "Cref", desc = "cleveref, sentence start" }, fmta("\\Cref{<>}", { i(1) })),

    s(
        "beg",
        fmta(
            [[
        \begin{<>}
            <>
        \end{<>}
    ]],
            { i(1), i(2), rep(1) }
        )
    ),
    s(
        "item",
        fmta(
            [[
        \begin{itemize}
            \item <>
        \end{itemize}
    ]],
            { i(1) }
        )
    ),
    s(
        "enum",
        fmta(
            [[
        \begin{enumerate}
            \item <>
        \end{enumerate}
    ]],
            { i(1) }
        )
    ),
    s(
        "fig",
        fmta(
            [[
        \begin{figure}[<>]
            \centering
            \includegraphics[width=<>\textwidth]{<>}
            \caption{<>}
            \label{figure:<>}
        \end{figure}
    ]],
            { i(1, "htbp"), i(2, "0.8"), i(3), i(4), i(5) }
        )
    ),
    s(
        "tab",
        fmta(
            [[
        \begin{table}[<>]
            \centering
            \begin{tabular}{<>}
                <>
            \end{tabular}
            \caption{<>}
            \label{table:<>}
        \end{table}
    ]],
            { i(1, "htbp"), i(2, "ccc"), i(3), i(4), i(5) }
        )
    ),

    s({ trig = "mk", desc = "inline math" }, fmta("$<>$", { i(1) }), { condition = not_math }),
    s(
        { trig = "dm", desc = "display math" },
        fmta(
            [[
        \[
            <>
        \]
    ]],
            { i(1) }
        ),
        { condition = not_math }
    ),
    s(
        { trig = "eq", desc = "numbered equation" },
        fmta(
            [[
        \begin{equation}
            \label{equation:<>}
            <>
        \end{equation}
    ]],
            { i(1), i(2) }
        )
    ),
    s(
        { trig = "ali", desc = "align*" },
        fmta(
            [[
        \begin{align*}
            <>
        \end{align*}
    ]],
            { i(1) }
        )
    ),
})

local autosnippets = {
    s({ trig = "//", desc = "fraction" }, fmta("\\frac{<>}{<>}", { i(1), i(2) }), { condition = in_math }),
    s({ trig = "sq", desc = "sqrt" }, fmta("\\sqrt{<>}", { i(1) }), { condition = math_not_command }),
    s(
        { trig = "sum", desc = "sum" },
        fmta("\\sum_{<>}^{<>}", { i(1, "i=1"), i(2, "n") }),
        { condition = math_not_command }
    ),
    s({ trig = "int", desc = "integral" }, fmta("\\int_{<>}^{<>}", { i(1), i(2) }), { condition = math_not_command }),
    s({ trig = "->", desc = "to" }, t("\\to "), { condition = in_math }),
    s({ trig = "!=", desc = "neq" }, t("\\neq "), { condition = in_math }),
    s(
        { trig = "([%a])(%d)", regTrig = true, desc = "auto subscript" },
        fmta("<>_{<>}", { cap(1), cap(2) }),
        { condition = in_math }
    ),
}

return snippets, autosnippets
