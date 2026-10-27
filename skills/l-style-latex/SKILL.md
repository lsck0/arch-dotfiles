---
name: l-style-latex
description: "Luca's conventions for LaTeX and mathematics: a thin main.tex composition root in five forms (amsart paper, book thesis, book multi-subject compendium, amsart homework/exam, beamer talk), one shared header.sty with opt-in package options, single-letter macro families, notation habits (coloneq, colon maps), a custom indexed amsthm style, cleveref namespaced labels and ids, and Lean formalization. Load alongside the l-style core when writing LaTeX, math, proofs, or formalization in Luca's name."
---

# l-style: LaTeX and math

The on-demand part of `l-style` for LaTeX and mathematics. Load the
`l-style` core first (the Writing hard rules apply to math prose too). The
philosophy carries over: idle costs nothing (opt-in package options),
single source of truth, primitives that compose (macro families).

Project layout. One `header.sty` and one `.latexmkrc` are shared by every form; `main.tex` is a thin composition root that picks the class and how content is split. The template's `main.tex` carries all five forms, the paper active and the other four commented below a `% ---- other kinds of document ----` rule, so a new project starts from one file. `geometry` margins are `left=2.5cm, right=2.5cm, top=3cm, bottom=3cm`; `babel` matches the document language. The five forms:

- Paper (a single result): `amsart`, `11pt`, `a4paper`. `main.tex` is `\documentclass`, `geometry`, `babel`, `\usepackage[<flags>]{header}`, metadata, then the abstract before `\maketitle` (amsart typesets it there), then one `\section{...}` plus `\input{src/NN_name.tex}` per section. Sections are flat gap-numbered files `src/00_introduction.tex`, `src/10_...`, leaving room to insert between. The abstract states the main theorem and result first, then what the article introduces and builds on.
- Thesis and long form: `book`, `11pt`, `a4paper`, options `[autolabels, ids]`. `\frontmatter`/`\mainmatter`/`\backmatter`, `\maketitle`, `\tableofcontents`, `\listoftodos[Todos]`, then one `\include{src/NN_name}` per chapter, each file opening with its own `\chapter`; `\backmatter` has `\printindex` and the bibliography. Chapters are gap-numbered `src/10_introduction.tex`.
- Compendium (lecture notes spanning many subjects): `book`, `10pt`, `a4paper`, more flags on (`diagrams, glossaries, graphs, autolabels, ids`). Content is nested two levels and letter-prefixed rather than gap-numbered: a subject directory per topic, each holding a per-subject aggregator file and letter-prefixed chapter files. The letter prefixes are a deliberate choice for a long-lived multi-subject tree and are kept; gap numbering stays for the paper and thesis `src/`.
- Homework and exams: `amsart`, `11pt`. Each task is `\begin{task}[<points>]` restating the prompt verbatim, then a sibling `\begin{solution}` (for compute/determine/answer) or a `proof` nested in the task or its item (for show/prove); parts as `enumerate[(a)]` or `[(i)]` matching the sheet. `\setcounter{task}{n-1}` skips an unassigned task, `\totalpoints`/`\pointsname` sums the points, `\hidesolutions[4cm]` turns the solution sheet into the blank exam. Language follows the course (`Sheet`/`Blatt`).
- Presentation: `beamer`, `11pt` (`10pt` for a dense talk), `\usetheme{boxes}`, same `header`. Title frame, an Outline frame with `\tableofcontents`, then one definition, lemma, theorem or example per frame with the main theorem stated before the machinery; a standing "Unless otherwise specified:" notation frame; `\pause`/overlays only to split a statement from its proof or to page a long computation; a References frame with `\nocite{*}` and `\bibliographystyle{alpha}`. A talk with a written handout ships an amsart handout carrying the same statements plus proofs, its abstract setting the result against a known analogue.

- All preamble lives in the local `header.sty`, loaded `\usepackage[<flags>]{header}`, never inline in `main.tex`. One-off macros for a single document go right after that line in `main.tex` via `\DeclareMathOperator`, `\NewDocumentCommand` or `\providecommand`, never a second preamble file; the old `\useTikz`/`\useDiagrams` feature switches are superseded by the package options.
- Build with latexmk and the project `.latexmkrc` (copied as is, never edited per project; it reads the header options out of `main.tex`): precompiled preamble, synctex on. The `ids` option stamps a stable id into each titled statement against an append-only ledger, so a reference survives a title rename. The `graphs` option renders a `.dot` graph through graphviz into a tikz figure at build time.
- New projects are scaffolded, not copied by hand: a small CLI stamps out a project directory with `header.sty`, `.latexmkrc`, `references.bib` and the `main.tex` template.
- Bibliography in `references.bib`, `\bibliographystyle{alpha}`, entries grouped under banner comments.

Preamble and macros:

- Organize `header.sty` with banner comments in the l-style house style: a lowercase `% ---- <name> ----` rule padded to the line width, not uppercase banner words. The sections, in order: `options`, `packages`, `optional packages`, `automatic labels`, `configuration` (with `theorems`, `chapters`, `homework and exams` as sub-rules inside it), `commands`, `auto-sized delimiters`. Options are declared with `\DeclareKeys`/`\ProcessKeyOptions`.
- Heavy packages and advanced features are opt-in package options, all off by default: `\usepackage[diagrams, autolabels]{header}` with `tikz`, `diagrams`, `plots`, `graphs`, `graphics`, `code`, `algorithms`, `asymptote`, `glossaries`, `autolabels`, `ids`. `graphs` renders `\graphlayout` graphs from graphviz; `diagrams`, `graphs` and `plots` each imply `tikz`. Idle costs nothing.
- Systematic single-letter macro families, each letter mapped to one font: `\A` to `\Z` blackboard bold, `\bA` to `\bZ` bold, `\cA` to `\cZ` calligraphic, `\sA` to `\sZ` sans (categories), `\fA` to `\fZ` and lowercase `\fa` to `\fz` fraktur (`\fp` for a prime, `\fii` for a fraktur i). Var shortcuts `\vphi`, `\vep`, `\vth`. Upright constants and differentials `\ce`, `\ci`, `\cd`, `\dx`, `\dt`. Utility macros `\Sp`, `\Res`, `\inv` (preimage), `\del`, `\case{...}`, `\mat{...}`, `\Zmod{n}`, `\faktor`; quotes via `\enquote{}` (csquotes), never literal `"`. The obsolete `\Cu`/`\Pa` are gone, since plain delimiters auto-size.
- Plain `( ) [ ] \{ \} | \|` in math auto-size via the header, so no hand-written `\left(`. Macros for the rest: `\Sp`, `\Abs`, `\Norm`, `\Res`.
- Named operators via `\DeclareMathOperator` (`\im`, `\id`, `\rk`, `\tr`), with the starred form where the index goes below (`\colim`); categories as `\mathsf` (`\Set`, `\Top`, `\Mfd`), invariants as their own operator (`\TC`, `\cat`, `\secat`, `\wgt`, `\zcl`). Derivative helpers `\derivative`/`\pderivative` via `\NewDocumentCommand`; never redefine a kernel or amsmath macro (`\dfrac`), and letter macros that shadow text commands (`\S`, `\P`, ...) switch on math mode.
- German documents (babel main language german) get German theorem, cref and task names from the header.

Notation habits:

- `\coloneq` is the definitional-equality symbol, used everywhere a term is defined. Plain `=` is only for equalities.
- Maps use `\colon`, never a bare `:`. Encode structure in the arrow: `\twoheadrightarrow` for surjections, `\hookrightarrow` for injections and sections.
- `\emph` a term on first introduction. Abbreviations with a thin space: `i.\,e.,`, `z.\,B.`, `d.\,h.`; German dates `15.\,07.\,2026`.
- `align*` for a multi-line display and as the notes house default. A single displayed line may use `\[ ... \]` in sheets and talks; numbered `equation`/`align` is fine in talks and handouts where a line is referred to aloud, but in papers and the notes a numbered environment is only for a line that is actually labelled and referenced.
- In a computation, put one equality per `align*` line, never a `&= \dots` elision in a final write-up. Name the tool in the sentence at the point it is used. Annotate a step on the relation: `\overset{\text{reason}}{=}`, `\overset{\cong}{=}`, `\overset{!}{=}`; name a term with `\underbrace{...}_{\text{reason or value}}`.

Theorems, proofs, references:

- `amsthm` with a custom `indexed` style (`\newtheoremstyle{indexed}`: upright body, bold head), not `\theoremstyle{definition}`. `theorem` is numbered off `[section]`; every other environment is its own `\newaliascnt` of `theorem`, so the shared counter advances once and `\cref` still prints the right name. The environments: `lemma`, `corollary`, `proposition`, `definition`, `example`, `exercise`, `problem`, `axiom`, `remark`, `conjecture`, plus starred unnumbered variants (`exercise*`) and `diagram`/`diagram*`. German documents get German heads and cref names from the header.
- Definitions and theorems carry a bracketed title in Title Case: `\begin{definition}[<Title Case Name>]`. With `ids` the form is `[<Title>|ABCDE]` (the stable id survives a title rename); a seminar following a source may prefix its numbering, `[4.2.3, <Name>]`. In notes and handouts the head ends `~\\` so the body starts on a new line.
- The `proof` environment is nested inside its statement environment as the last block, not written separately after it.
- Reference with `cleveref` `\cref` throughout (`nameinlink`), never a raw `\ref`. Set `\crefname` for every environment including irregular plurals (`Lemmata`).
- Labels are namespaced by the kind written out, never abbreviated, with a kebab-case descriptive slug: `definition:<slug>`, `theorem:<slug>`, `lemma:...`, `corollary:...`, `example:...`, `axiom:...`, `remark:...`, `conjecture:...`, `equation:...`, `chapter:...`, `section:...`, `subsection:...`. Diagrams labelled with `\label[diagram]{diagram:...}`.
  - The `autolabels` flag generates exactly these from titles: `\section{Set Theory}` gets `section:set-theory`, `\begin{lemma}[Zorn]` gets `lemma:zorn`. Hand-written labels follow the same scheme.
  - The `ids` flag adds a stable `<kind>:<ID>` per theorem from a title like `[Zorn|B6AFE]`, which survives renaming the title; reference it where the title may change.
  - This namespaced kebab form is the current rule for new or edited labels. Older documents use an abbreviated snake_case form (`def:`, `thm:`, `lem:`); leave those as they are unless asked, do not migrate.
- Cite with `\cite{bibkey}`, locators as `\cite[Proposition 2]{bibkey}`. bib keys are short descriptive slugs.
- Commutative diagrams via `tikz-cd` inside the custom centered `\begin{diagram}` environment. Mark pullback and pushout corners with `\ulcorner`/`\lrcorner` (`phantom`, `very near start`), use `bend`/`shift` for parallel and curved arrows.
- Draft markers live as macros, not stray text: `\todo`, `\citationneeded`, `\referenceneeded`, color helpers `\inred` and friends. Remove them before the final build.
- Keep the source free of literal `---`, `--` and unicode dashes in prose (the Writing hard rules apply to math prose): ranges in prose with `to`/`bis`, in math with `\dots` or an interval.

## Lean formalization

When a proof is formalized rather than only typeset, use Lean (`elan`
installed: `elan`, `lean`, `lake`). The core naming and single-source-of-truth
rules carry over: one definition per concept, named for what it is.

- Match the informal statement exactly: the Lean `theorem` name and its
  LaTeX `\label` slug describe the same result, so paper and formalization
  cross-reference cleanly.
- A definition in Lean mirrors the `\coloneq` definition in the text; the
  two never drift, same as code against a spec.
- `lake` is the build entry point; pin the toolchain via `lean-toolchain`
  and commit the lockfile, same pinning discipline as any other project.
