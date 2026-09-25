-- LaTeX luasnip snippets: sections, environments, and math (autosnippets in math zones).
local ls = require("luasnip")
local s = ls.snippet
local i = ls.insert_node
local t = ls.text_node
local f = ls.function_node
local fmta = require("luasnip.extras.fmt").fmta
local rep = require("luasnip.extras").rep

ls.config.set_config({ enable_autosnippets = true })

-- vimtex's zone check; pcall-guarded so it is safe before vimtex finishes loading
local function in_math()
    local ok, res = pcall(vim.fn["vimtex#syntax#in_mathzone"])
    return ok and res == 1
end
local function math() return in_math() end
local function not_math() return not in_math() end

-- capture group N of a regex trigger, verbatim
local function cap(n)
    return f(function(_, snip) return snip.captures[n] end)
end

ls.add_snippets("tex", {
    -- sections
    s("sec", fmta("\\section{<>}<>", { i(1), i(0) })),
    s("ssec", fmta("\\subsection{<>}<>", { i(1), i(0) })),
    s("sssec", fmta("\\subsubsection{<>}<>", { i(1), i(0) })),
    s("par", fmta("\\paragraph{<>}<>", { i(1), i(0) })),

    -- environments
    s("beg", fmta([[
        \begin{<>}
            <>
        \end{<>}
    ]], { i(1), i(2), rep(1) })),
    s("item", fmta([[
        \begin{itemize}
            \item <>
        \end{itemize}
    ]], { i(1) })),
    s("enum", fmta([[
        \begin{enumerate}
            \item <>
        \end{enumerate}
    ]], { i(1) })),
    s("fig", fmta([[
        \begin{figure}[<>]
            \centering
            \includegraphics[width=<>\textwidth]{<>}
            \caption{<>}
            \label{fig:<>}
        \end{figure}
    ]], { i(1, "htbp"), i(2, "0.8"), i(3), i(4), i(5) })),
    s("tab", fmta([[
        \begin{table}[<>]
            \centering
            \begin{tabular}{<>}
                <>
            \end{tabular}
            \caption{<>}
            \label{tab:<>}
        \end{table}
    ]], { i(1, "htbp"), i(2, "ccc"), i(3), i(4), i(5) })),

    -- math environments
    s({ trig = "mk", desc = "inline math" }, fmta("$<>$", { i(1) }), { condition = not_math }),
    s({ trig = "dm", desc = "display math" }, fmta([[
        \[
            <>
        \]
    ]], { i(1) }), { condition = not_math }),
    s({ trig = "eq", desc = "equation" }, fmta([[
        \begin{equation}
            <>
        \end{equation}
    ]], { i(1) })),
    s({ trig = "ali", desc = "align" }, fmta([[
        \begin{align}
            <>
        \end{align}
    ]], { i(1) })),

    -- math autosnippets (only fire inside a math zone)
    s({ trig = "//", desc = "fraction", snippetType = "autosnippet" },
        fmta("\\frac{<>}{<>}", { i(1), i(2) }), { condition = math }),
    s({ trig = "sq", desc = "sqrt", snippetType = "autosnippet" },
        fmta("\\sqrt{<>}", { i(1) }), { condition = math }),
    s({ trig = "sum", desc = "sum", snippetType = "autosnippet" },
        fmta("\\sum_{<>}^{<>}", { i(1, "i=1"), i(2, "n") }), { condition = math }),
    s({ trig = "int", desc = "integral", snippetType = "autosnippet" },
        fmta("\\int_{<>}^{<>}", { i(1), i(2) }), { condition = math }),
    s({ trig = "->", desc = "to", snippetType = "autosnippet" }, t("\\to "), { condition = math }),
    s({ trig = "!=", desc = "neq", snippetType = "autosnippet" }, t("\\neq "), { condition = math }),
    s({ trig = "([%a])(%d)", regTrig = true, desc = "auto subscript", snippetType = "autosnippet" },
        fmta("<>_{<>}", { cap(1), cap(2) }), { condition = math }),
})
