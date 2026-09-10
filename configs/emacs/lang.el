;;; lang.el --- treesitter, LSP, diagnostics, formatting -*- lexical-binding: t; -*-
;; treesit + eglot + flymake are all built in; only the glue is packaged.

;;;; treesitter --------------------------------------------------------------

(setq treesit-font-lock-level 4)

;; nvim-treesitter -> auto-install grammars and route major modes to *-ts-mode
(use-package treesit-auto
  :init (setq treesit-auto-install 'prompt)
  :config
  (treesit-auto-add-to-auto-mode-alist 'all)
  (global-treesit-auto-mode 1))

;;;; LSP ---------------------------------------------------------------------

(use-package eglot
  :ensure nil
  :hook ((c-mode c-ts-mode c++-mode c++-ts-mode
          rust-ts-mode python-mode python-ts-mode
          js-ts-mode typescript-ts-mode tsx-ts-mode
          bash-ts-mode sh-mode css-ts-mode html-mode
          json-ts-mode yaml-ts-mode lua-ts-mode go-ts-mode
          zig-mode nix-mode haskell-mode) . eglot-ensure)
  :config
  (setq eglot-autoshutdown t
        eglot-events-buffer-size 0        ; don't log every LSP message
        eglot-extend-to-xref t)

  ;; inlay-hints.nvim
  (add-hook 'eglot-managed-mode-hook
            (lambda () (when (eglot-managed-p) (eglot-inlay-hints-mode 1))))

  (add-to-list 'eglot-server-programs
               '((c-mode c-ts-mode c++-mode c++-ts-mode)
                 . ("clangd" "--offset-encoding=utf-16" "--background-index")))
  (add-to-list 'eglot-server-programs
               '(jai-mode . ("jails" "-jai_path" "/home/luca/.jai"
                             "-jai_exe_name" "jai-linux")))

  ;; rust-analyzer: allFeatures + kani cfg flags + nightly clippy (nvim parity)
  (setq-default eglot-workspace-configuration
                '(:rust-analyzer
                  (:cargo (:allFeatures t
                           :extraEnv (:RUSTFLAGS "--cfg kani_ra --cfg kani"
                                      :RUSTUP_TOOLCHAIN "nightly"))
                   :check (:command "clippy"
                           :extraEnv (:RUSTFLAGS "--cfg kani_ra --cfg kani"
                                      :RUSTUP_TOOLCHAIN "nightly"))))))

;; floating hover box (SPC l i), instead of the echo-area one-liner
(use-package eldoc-box
  :hook (eglot-managed-mode . eldoc-box-hover-at-point-mode))

;;;; diagnostics -------------------------------------------------------------

(use-package flymake
  :ensure nil
  :hook (prog-mode . flymake-mode)
  :config
  ;; nvim diagnostics virtual_text; built in since Emacs 30, so no sideline
  (setq flymake-show-diagnostics-at-end-of-line 'short
        flymake-no-changes-timeout 0.5))

;;;; formatting --------------------------------------------------------------

;; conform.nvim -> apheleia, async format-on-save (never blocks the cursor)
(use-package apheleia
  :init (apheleia-global-mode 1)
  :config
  ;; isort + black for python
  (setf (alist-get 'python-mode    apheleia-mode-alist) '(isort black)
        (alist-get 'python-ts-mode apheleia-mode-alist) '(isort black))
  (dolist (m '(c-mode c-ts-mode c++-mode c++-ts-mode))
    (setf (alist-get m apheleia-mode-alist) 'clang-format))
  ;; rust: rustfmt -> leptosfmt -> sortderives. Missing binaries are skipped.
  (setf (alist-get 'leptosfmt   apheleia-formatters) '("leptosfmt" "--stdin" "--rustfmt")
        (alist-get 'sortderives apheleia-formatters) '("sort-derives-stdout"))
  (dolist (m '(rust-mode rust-ts-mode))
    (setf (alist-get m apheleia-mode-alist) '(rustfmt leptosfmt sortderives)))
  (dolist (m '(typescript-ts-mode tsx-ts-mode js-ts-mode
               html-mode css-ts-mode scss-mode))
    (setf (alist-get m apheleia-mode-alist) 'prettier)))

;;;; major modes not bundled with Emacs --------------------------------------
;; Rust, Go, Lua, Python, JS/TS, C/C++, JSON, YAML, bash and friends all have
;; built-in *-ts-mode; treesit-auto wires them up. Only these are missing.

(use-package haskell-mode :defer t)
(use-package zig-mode     :defer t)
(use-package nix-mode     :defer t)
(use-package just-mode    :mode "[Jj]ustfile\\'")

(use-package markdown-mode
  :mode ("\\.md\\'" . gfm-mode)
  :config (setq markdown-fontify-code-blocks-natively t))

(use-package jai-mode
  :vc (:url "https://github.com/elp-revive/jai-mode" :rev :newest)
  :mode "\\.jai\\'"
  :hook (jai-mode . eglot-ensure))

(provide 'lang)
;;; lang.el ends here
