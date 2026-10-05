---
name: l-style-latex
description: "Luca's conventions for LaTeX and mathematics: thin main.tex composition root, gap-numbered source files, a local header.sty with opt-in package options, single-letter macro families, notation habits (coloneq, colon maps, align* default), amsthm theorems, cleveref namespaced labels, and Lean formalization. Load alongside the l-style core when writing LaTeX, math, proofs, or formalization in Luca's name."
---

# l-style: LaTeX and math

The on-demand part of `l-style` for LaTeX and mathematics. Load the
`l-style` core first (the Writing hard rules apply to math prose too). The
philosophy carries over: idle costs nothing (opt-in package options),
single source of truth, primitives that compose (macro families).

Project layout:

- `main.tex` is a thin composition root: `\documentclass`, `\usepackage[<feature flags>]{header}`, metadata, then one `\section{...}` plus `\input{src/NN_name.tex}` per section. No content lives in it.
- Content lives in gap-numbered source files, `src/00_introduction.tex`, `src/10_tc.tex`, `src/20_...`, leaving room to insert between.
- All preamble lives in a local package `header.sty` loaded with `\usepackage{header}`, never inline in `main.tex`.
- Build with latexmk and the project `.latexmkrc`: precompiled preamble, synctex always on, ids stamped when the `ids` flag is set. It reads the header options from `main.tex`, so it is copied as is and never edited per project.
- `amsart`, `11pt`, `a4paper`. `geometry` for margins, `babel` matching the document language. Bibliography in `references.bib`, `\bibliographystyle{alpha}`, entries grouped under banner comments.
- The abstract states the main theorem and result up front, then says what the article introduces and builds on.

Preamble and macros:

- Organize `header.sty` with banner comments: `OPTIONS`, `PACKAGES`, `OPTIONAL PACKAGES`, `AUTOMATIC LABELS`, `CONFIGURATION`, `THEOREMS`, `HOMEWORK AND EXAMS`, `COMMANDS`, sub-grouped (util, essential math).
- Heavy packages and advanced features are opt-in package options, all off by default: `\usepackage[diagrams, autolabels]{header}` with `tikz`, `diagrams`, `plots`, `graphics`, `code`, `algorithms`, `asymptote`, `glossaries`, `autolabels`, `ids`. Idle costs nothing.
- Systematic single-letter macro families: `\A` to `\Z` blackboard bold, `\cA` to `\cZ` calligraphic, `\fA` to `\fZ` fraktur. Var shortcuts `\vphi`, `\vep`, `\vth`. Upright constants and differentials `\ce`, `\ci`, `\cd`, `\dx`, `\dt`.
- Plain `( ) [ ] \{ \} | \|` in math auto-size via the header, so no hand-written `\left(`. Macros for the rest: `\Sp`, `\Abs`, `\Norm`, `\Res`.
- Named operators via `\DeclareMathOperator` (`\im`, `\id`, `\rk`, `\tr`), with the starred form where the index goes below (`\colim`); categories as `\mathsf` (`\Set`, `\Top`, `\Mfd`), invariants as their own operator (`\TC`, `\cat`, `\secat`, `\wgt`, `\zcl`). Derivative helpers `\derivative`/`\pderivative` via `\NewDocumentCommand`; never redefine a kernel or amsmath macro (`\dfrac`), and letter macros that shadow text commands (`\S`, `\P`, ...) switch on math mode.
- German documents (babel main language german) get German theorem, cref and task names from the header.

Notation habits:

- `\coloneq` is the definitional-equality symbol, used everywhere a term is defined. Plain `=` is only for equalities.
- Maps use `\colon`, never a bare `:`. Encode structure in the arrow: `\twoheadrightarrow` for surjections, `\hookrightarrow` for injections and sections.
- `\emph` a term on first introduction. `i.\,e.,` with a thin space, and spelled that way.
- `align*` is the default display environment. Use `equation` only when the line needs a number and label. Annotate step equalities with `\overset{!}{=}`, `\overset{\cong}{=}`, `\overset{\text{nat.}}{\implies}`.

Theorems, proofs, references:

- `amsthm`, `\theoremstyle{definition}`. One shared counter off `[section]`: `\newtheorem{theorem}{Theorem}[section]`, every other environment numbered `[theorem]` (`lemma`, `corollary`, `definition`, `example`, `axiom`, `remark`, `conjecture`).
- Definitions and theorems carry a bracketed title: `\begin{definition}[topological complexity]`.
- The `proof` environment is nested inside its statement environment as the last block, not written separately after it.
- Reference with `cleveref` `\cref` throughout (`nameinlink`), never a raw `\ref`. Set `\crefname` for every environment including irregular plurals (`Lemmata`).
- Labels are namespaced by the kind written out, never abbreviated, with a kebab-case descriptive slug: `definition:path-loop-space`, `theorem:cts-motion-planner-exists-iff-contractible`, `lemma:...`, `corollary:...`, `example:...`, `axiom:...`, `remark:...`, `conjecture:...`, `equation:...`, `chapter:...`, `section:...`, `subsection:...`. Diagrams labelled with `\label[diagram]{diagram:...}`.
  - The `autolabels` flag generates exactly these from titles: `\section{Set Theory}` gets `section:set-theory`, `\begin{lemma}[Zorn]` gets `lemma:zorn`. Hand-written labels follow the same scheme.
  - The `ids` flag adds a stable `<kind>:<ID>` per theorem from `[Zorn|B6AFE]`, which survives renaming the title; reference it where the title may change.
- Cite with `\cite{bibkey}`, locators as `\cite[Proposition 2]{bibkey}`. bib keys are short descriptive slugs.
- Commutative diagrams via `tikz-cd` inside the custom centered `\begin{diagram}` environment. Mark pullback and pushout corners with `\ulcorner`/`\lrcorner` (`phantom`, `very near start`), use `bend`/`shift` for parallel and curved arrows.
- Draft markers live as macros, not stray text: `\todo`, `\citationneeded`, `\referenceneeded`, color helpers `\inred` and friends. Remove them before the final build.

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
