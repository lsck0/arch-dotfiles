-- run by citation.test.nu: nvim --clean -l citation.test.lua <config dir> <scratch dir>
local config, dir = arg[1], arg[2]
package.path = config .. "/lua/?.lua;" .. package.path
local citation = require("lib.citation")

local failures = {}
local function expect(name, got, want)
    if not vim.deep_equal(got, want) then
        failures[#failures + 1] = string.format("%s: got %s, want %s", name, vim.inspect(got), vim.inspect(want))
    end
end

vim.fn.writefile({
    "@article{farber2003,",
    "  author = {Farber, Michael},",
    "  booktitle = {Not the title},",
    "  title = {Topological complexity of motion {P}lanning},",
    "  year = {2003},",
    "}",
    '@Book{hatcher2002, Author = "Hatcher, Allen and Doe, John and Roe, Richard", Title = {Algebraic \\emph{Topology}},',
    "  date = {2002-01-01}}",
    '@string{journal = "skipped"}',
}, dir .. "/references.bib")
vim.fn.writefile({
    "@book{farber2003, title = {Shadowed by the project}, year = 1999}",
    "@book{zotero2020, author = {Solo, Han}, title = {Only in Zotero}, year = 2020}",
}, dir .. "/library.bib")
citation.ZOTERO_BIB = dir .. "/library.bib"

local function buffer(name, filetype, lines)
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, dir .. "/" .. name)
    vim.bo[buf].filetype = filetype
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_set_current_buf(buf)
    return buf
end

local tex = buffer("main.tex", "tex", { "See \\cite{farber2003} here.", "Plain text.", "\\citep[Proposition 2]{}" })
expect(
    "entries",
    vim.tbl_map(function(e)
        return { e.key, e.author, e.year, e.title, vim.fs.basename(e.file) }
    end, citation.entries(tex)),
    {
        { "farber2003", "Farber", "2003", "Topological complexity of motion Planning", "references.bib" },
        { "hatcher2002", "Hatcher, Doe et al.", "2002", "Algebraic Topology", "references.bib" },
        { "zotero2020", "Solo", "2020", "Only in Zotero", "library.bib" },
    }
)

local function insert_at(row, col, key)
    vim.api.nvim_win_set_cursor(0, { row, col })
    citation.insert(key)
    return vim.api.nvim_get_current_line()
end
expect("tex into cite", insert_at(1, 12, "hatcher2002"), "See \\cite{farber2003,hatcher2002} here.")
expect("tex new cite", insert_at(2, 5, "hatcher2002"), "Plain \\cite{hatcher2002}text.")
expect("tex empty cite", insert_at(3, 3, "farber2003"), "\\citep[Proposition 2]{farber2003}")
expect("tex in cite", citation.in_cite("\\parencite[p. 3]{farber2003,", "tex"), true)
expect("tex after cite", citation.in_cite("\\cite{farber2003} and {", "tex"), false)
expect("tex other command", citation.in_cite("\\cite and \\emph{", "tex"), false)

buffer("notes.md", "markdown", { "A claim [@farber2003] here.", "Plain." })
expect("md into cite", insert_at(1, 12, "zotero2020"), "A claim [@farber2003; @zotero2020] here.")
expect("md new cite", insert_at(2, 5, "zotero2020"), "Plain.[@zotero2020]")
expect("md after @", citation.in_cite("see [@far", "markdown"), true)
expect("md email", citation.in_cite("mail a@b", "markdown"), false)

if #failures > 0 then
    io.stderr:write(table.concat(failures, "\n") .. "\n")
    os.exit(1)
end
