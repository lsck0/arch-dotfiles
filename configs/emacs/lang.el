;;; lang.el -*- lexical-binding: t; -*-
;; LSP (eglot), treesit, format-on-save (conform), debugging (dap), langs.

;; treesitter — auto-install grammars
(use-package treesit-auto
  :init (setq treesit-auto-install 'prompt)
  :config
  (treesit-auto-add-to-auto-mode-alist 'all)
  (global-treesit-auto-mode 1))

;; treesitter-context (sticky scope)
(use-package topsy
  :hook (prog-mode . topsy-mode))

;; LSP via builtin eglot
(use-package eglot
  :ensure nil
  :hook ((c-mode c-ts-mode c++-mode c++-ts-mode
          rust-ts-mode python-ts-mode python-mode
          js-ts-mode typescript-ts-mode tsx-ts-mode
          bash-ts-mode sh-mode css-ts-mode html-mode
          json-ts-mode yaml-ts-mode lua-ts-mode go-ts-mode
          haskell-mode latex-mode) . eglot-ensure)
  :config
  (setq eglot-autoshutdown t
        eglot-events-buffer-size 0
        eglot-extend-to-xref t)
  ;; inlay-hints.nvim / twoslash / better-type-hover -> eglot inlay hints
  (add-hook 'eglot-managed-mode-hook
            (lambda () (when (eglot-managed-p) (eglot-inlay-hints-mode 1))))
  (add-to-list 'eglot-server-programs
               '((c-mode c-ts-mode c++-mode c++-ts-mode)
                 . ("clangd" "--offset-encoding=utf-16" "--background-index")))
  ;; jails (nvim jai LSP)
  (add-to-list 'eglot-server-programs
               '(jai-mode . ("jails" "-jai_path" "/home/luca/.jai"
                             "-jai_exe_name" "jai-linux")))
  ;; rust-analyzer: allFeatures + kani cfg flags + nightly + clippy (nvim parity)
  (setq-default eglot-workspace-configuration
                '(:rust-analyzer
                  (:cargo (:allFeatures t
                           :extraEnv (:RUSTFLAGS "--cfg kani_ra --cfg kani"
                                      :RUSTUP_TOOLCHAIN "nightly"))
                   :check (:command "clippy"
                           :extraEnv (:RUSTFLAGS "--cfg kani_ra --cfg kani"
                                      :RUSTUP_TOOLCHAIN "nightly"))))))

;; nicer eldoc box for hover (better-type-hover / inlay-hints feel)
(use-package eldoc-box
  :hook (eglot-managed-mode . eldoc-box-hover-at-point-mode))

;; conform.nvim -> apheleia (format on save, async)
(use-package apheleia
  :init (apheleia-global-mode 1)
  :config
  ;; isort + black for python, like nvim conform
  (setf (alist-get 'python-mode    apheleia-mode-alist) '(isort black)
        (alist-get 'python-ts-mode apheleia-mode-alist) '(isort black)
        (alist-get 'latex-mode     apheleia-formatters) '("latexindent" "-"))
  ;; C/Rust/TS/HTML/CSS formatters (clang-format/rustfmt/prettier are builtin)
  (dolist (m '(c-ts-mode c++-ts-mode))
    (setf (alist-get m apheleia-mode-alist) 'clang-format))
  ;; rust: rustfmt -> leptosfmt -> sortderives chain (nvim conform). leptosfmt
  ;; and sortderives are skipped gracefully if their binaries are absent.
  (setf (alist-get 'leptosfmt apheleia-formatters) '("leptosfmt" "--stdin" "--rustfmt")
        (alist-get 'sortderives apheleia-formatters) '("sort-derives-stdout"))
  (dolist (m '(rust-mode rust-ts-mode))
    (setf (alist-get m apheleia-mode-alist) '(rustfmt leptosfmt sortderives)))
  (dolist (m '(typescript-ts-mode tsx-ts-mode js-ts-mode
               html-mode css-ts-mode scss-mode))
    (setf (alist-get m apheleia-mode-alist) 'prettier)))

;; nvim-dap -> dape
(use-package dape
  :init (setq dape-buffer-window-arrangement 'right)
  :config (add-hook 'dape-compile-hook 'kill-buffer))

;; languages without bundled major modes
(use-package rust-mode :defer t)
(use-package lua-mode :defer t)
(use-package haskell-mode :defer t)
(use-package zig-mode :defer t)
(use-package nix-mode :defer t)
(use-package go-mode :defer t)

;; jai (rluba/jai.vim -> jai-mode) + jails LSP
(use-package jai-mode
  :vc (:url "https://github.com/elp-revive/jai-mode" :rev :newest)
  :mode "\\.jai\\'"
  :hook (jai-mode . eglot-ensure))

;; tree-sitter-just (justfile support)
(use-package just-mode :mode "[Jj]ustfile\\'")

;; markdown (render-markdown.nvim)
(use-package markdown-mode
  :mode ("\\.md\\'" . gfm-mode)
  :config (setq markdown-fontify-code-blocks-natively t))

;; LaTeX (vimtex) — auctex + texlab LSP, okular + in-emacs pdf-tools
(use-package auctex
  :defer t
  :hook ((LaTeX-mode . eglot-ensure)
         (LaTeX-mode . turn-on-cdlatex)
         (LaTeX-mode . TeX-source-correlate-mode))
  :config
  (setq TeX-auto-save t
        TeX-parse-self t
        TeX-source-correlate-start-server t
        TeX-view-program-selection '((output-pdf "Okular"))))

(use-package cdlatex :after auctex)

(use-package pdf-tools
  :magic ("%PDF" . pdf-view-mode)
  :config (pdf-tools-install :no-query))

;; flymake diagnostics nav
(use-package flymake
  :ensure nil
  :hook (prog-mode . flymake-mode)
  :config (setq flymake-show-diagnostics-at-end-of-line nil))

;; inline diagnostics at end of line (nvim virtual_text), not just on hover
(use-package sideline
  :hook (flymake-mode . sideline-mode)
  :init (setq sideline-backends-right '(sideline-flymake)
              sideline-display-backend-name nil
              sideline-delay 0.2))
(use-package sideline-flymake
  :after sideline
  :init (setq sideline-flymake-display-mode 'line))

(provide 'lang)
;;; lang.el ends here
