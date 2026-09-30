;;; lang.el --- treesitter, LSP, diagnostics, formatting -*- lexical-binding: t; -*-

;;;; treesitter --------------------------------------------------------------

(setq treesit-font-lock-level 4)

;; auto-install grammars, route major modes to *-ts-mode
(use-package treesit-auto
  :init (setq treesit-auto-install 'prompt)
  :config
  (treesit-auto-add-to-auto-mode-alist 'all)
  (global-treesit-auto-mode 1))

;;;; LSP ---------------------------------------------------------------------

(defun my/cargo-toml-mentions-p (word)
  "Non-nil when the nearest Cargo.toml above `default-directory' contains WORD."
  (when-let* ((root (locate-dominating-file default-directory "Cargo.toml")))
    (with-temp-buffer
      (insert-file-contents (expand-file-name "Cargo.toml" root))
      (search-forward word nil t))))

(defun my/eglot-workspace-configuration (_server)
  "Rust-analyzer settings, with the kani cfgs and nightly only in kani projects."
  (let ((env (when (my/cargo-toml-mentions-p "kani")
               '(:extraEnv (:RUSTFLAGS "--cfg kani_ra --cfg kani" :RUSTUP_TOOLCHAIN "nightly")))))
    `(:rust-analyzer
      (:cargo (:allFeatures t ,@env)
       :check (:command "clippy" ,@env)))))

(use-package eglot
  :ensure nil
  :hook ((c-mode c-ts-mode c++-mode c++-ts-mode
          rust-ts-mode python-mode python-ts-mode
          js-ts-mode typescript-ts-mode tsx-ts-mode
          bash-ts-mode sh-mode css-ts-mode html-mode
          json-ts-mode yaml-ts-mode lua-ts-mode go-ts-mode
          ruby-ts-mode ruby-mode markdown-mode gfm-mode
          latex-mode tex-mode bibtex-mode LaTeX-mode
          zig-mode nix-mode haskell-mode) . eglot-ensure)
  :config
  (setq eglot-autoshutdown t
        eglot-events-buffer-size 0        ; don't log every LSP message
        eglot-extend-to-xref t)

  (add-hook 'eglot-managed-mode-hook
            (lambda () (when (eglot-managed-p) (eglot-inlay-hints-mode 1))))

  ;; builtin eglot has no texlab entry
  (add-to-list 'eglot-server-programs
               '((latex-mode tex-mode bibtex-mode LaTeX-mode)
                 . ("texlab")))

  (add-to-list 'eglot-server-programs
               '((c-mode c-ts-mode c++-mode c++-ts-mode)
                 . ("clangd" "--offset-encoding=utf-16" "--background-index")))
  (add-to-list 'eglot-server-programs
               '(jai-mode . ("jails" "-jai_path" "/home/luca/.jai"
                             "-jai_exe_name" "jai-linux")))

  (add-to-list 'eglot-server-programs '((markdown-mode gfm-mode) . ("marksman")))

  ;; eglot binds default-directory to the project root before calling this
  (setq-default eglot-workspace-configuration #'my/eglot-workspace-configuration))

(use-package consult-eglot
  :commands (consult-eglot-symbols))
(use-package git-link
  :commands (git-link git-link-homepage)
  :config (setq git-link-open-in-browser t))

;; floating hover box instead of the echo area
(use-package eldoc-box
  :hook (eglot-managed-mode . eldoc-box-hover-at-point-mode))

;;;; diagnostics -------------------------------------------------------------

(use-package flymake
  :ensure nil
  :hook (prog-mode . flymake-mode)
  :config
  ;; built in since emacs 30, so no sideline package
  (setq flymake-show-diagnostics-at-end-of-line 'short
        flymake-no-changes-timeout 0.5))

;;;; formatting --------------------------------------------------------------

;; async format-on-save
(use-package apheleia
  :init (apheleia-global-mode 1)
  :config
  (setf (alist-get 'python-mode    apheleia-mode-alist) '(isort black)
        (alist-get 'python-ts-mode apheleia-mode-alist) '(isort black))
  (dolist (m '(c-mode c-ts-mode c++-mode c++-ts-mode))
    (setf (alist-get m apheleia-mode-alist) 'clang-format))
  ;; missing formatter binaries are skipped
  (setf (alist-get 'leptosfmt   apheleia-formatters) '("leptosfmt" "--stdin" "--rustfmt")
        (alist-get 'sortderives apheleia-formatters) '("sort-derives-stdout"))
  (dolist (m '(rust-mode rust-ts-mode))
    (setf (alist-get m apheleia-mode-alist) '(rustfmt sortderives)))
  ;; leptosfmt only in leptos projects, else it errors on plain Rust
  (dolist (hook '(rust-mode-hook rust-ts-mode-hook))
    (add-hook hook (lambda ()
                     (when (my/cargo-toml-mentions-p "leptos")
                       (setq-local apheleia-formatter '(rustfmt leptosfmt sortderives))))))
  (dolist (m '(typescript-ts-mode tsx-ts-mode js-ts-mode
               html-mode css-ts-mode scss-mode))
    (setf (alist-get m apheleia-mode-alist) 'prettier))
  (setf (alist-get 'gofumpt apheleia-formatters) '("gofumpt")
        (alist-get 'nixfmt  apheleia-formatters) '("nixfmt"))
  (dolist (m '(go-mode go-ts-mode))     (setf (alist-get m apheleia-mode-alist) '(goimports gofumpt)))
  (dolist (m '(sh-mode bash-ts-mode))   (setf (alist-get m apheleia-mode-alist) 'shfmt))
  (dolist (m '(lua-mode lua-ts-mode))   (setf (alist-get m apheleia-mode-alist) 'stylua))
  (dolist (m '(nix-mode nix-ts-mode))   (setf (alist-get m apheleia-mode-alist) 'nixfmt)))

;;;; major modes not bundled with Emacs --------------------------------------

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

;;;; notebooks (molten + jupytext.nvim) --------------------------------------

;; `# %%` cells, .ipynb round-trip via jupytext
(use-package code-cells
  :hook ((python-mode python-ts-mode markdown-mode) . code-cells-mode-maybe))

(provide 'lang)
;;; lang.el ends here
