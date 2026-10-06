;; tempel templates, mirroring nvim's lua/snippets.lua and lua/latex_snippets.lua

c-mode c-ts-mode c++-mode c++-ts-mode js-mode js-ts-mode typescript-ts-mode tsx-ts-mode

(banner n "/*" n " * " (make-string 117 ?-) n " * " p n " * " (make-string 117 ?-) n " */" n)
(smallbanner n "/*" n " * " (make-string 57 ?-) n " * " p n " * " (make-string 57 ?-) n " */" n)

c-mode c-ts-mode

(sec "/*" n " * " (make-string 77 ?-) n " * " (p "SECTION") n " * " (make-string 77 ?-) n " */" n)
(const "// " (p "why: measured against, trades off, breaks above/below") n "#define " (p "NAME") " " (p "value"))
(assert "assert(" (p "cond") ");")
(brief "/** @brief " (p "summary") " */")
(param "@param " (p "name") " " (p "desc"))
(return "@return " (p "desc"))
(doc "/**" n " * @brief " (p "summary") n " *" n " * @param " (p "name") " " (p "desc")
     n " * @return " (p "desc") n " */")

python-mode python-ts-mode

(banner n "#" n "# " (make-string 117 ?-) n "# " p n "# " (make-string 117 ?-) n "#" n)
(smallbanner n "#" n "# " (make-string 57 ?-) n "# " p n "# " (make-string 57 ?-) n "#" n)

lua-mode lua-ts-mode

(banner n "--" n "-- " (make-string 117 ?-) n "-- " p n "-- " (make-string 117 ?-) n "--" n)
(smallbanner n "--" n "-- " (make-string 57 ?-) n "-- " p n "-- " (make-string 57 ?-) n "--" n)

rust-mode rust-ts-mode

(struct "#[derive(Debug, Clone)]" n "pub struct " (p "Name") " {" n "}")
(enum "#[derive(Debug, Clone)]" n "pub enum " (p "Name") " {" n "}")

LaTeX-mode plain-TeX-mode

(banner n "%" n "% " (make-string 117 ?-) n "% " p n "% " (make-string 117 ?-) n "%" n)
(smallbanner n "%" n "% " (make-string 57 ?-) n "% " p n "% " (make-string 57 ?-) n "%" n)
(sec "\\section{" p "}" q)
(ssec "\\subsection{" p "}" q)
(sssec "\\subsubsection{" p "}" q)
(par "\\paragraph{" p "}" q)
(beg "\\begin{" (s env) "}" n> p n "\\end{" env "}" >)
(item "\\begin{itemize}" n> "\\item " p n "\\end{itemize}" >)
(enum "\\begin{enumerate}" n> "\\item " p n "\\end{enumerate}" >)
(fig "\\begin{figure}[" (p "htbp") "]" n> "\\centering" n> "\\includegraphics[width=" (p "0.8") "\\textwidth]{" p "}"
     n> "\\caption{" p "}" n> "\\label{fig:" p "}" n "\\end{figure}" >)
(tab "\\begin{table}[" (p "htbp") "]" n> "\\centering" n> "\\begin{tabular}{" (p "ccc") "}" n> p n "\\end{tabular}" >
     n> "\\caption{" p "}" n> "\\label{tab:" p "}" n "\\end{table}" >)
(mk "$" p "$" :when (not (texmathp)))
(dm "\\[" n> p n "\\]" > :when (not (texmathp)))
(eq "\\begin{equation}" n> p n "\\end{equation}" >)
(ali "\\begin{align}" n> p n "\\end{align}" >)
