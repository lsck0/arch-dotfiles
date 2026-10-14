;;; lang.el --- treesitter, LSP, diagnostics, formatting -*- lexical-binding: t; -*-

(setq treesit-font-lock-level 4)

(use-package treesit-auto
  :init (setq treesit-auto-install 'prompt)
  :config
  (treesit-auto-add-to-auto-mode-alist 'all)
  (global-treesit-auto-mode 1))

(defconst my/treesit-langs
  '(bash c cmake cpp css dockerfile go haskell html javascript jsdoc json lua make markdown nix python ruby rust toml
    tsx typescript typst yaml zig)
  "Grammars the dotfiles build ahead: the languages with an LSP below plus config formats; others still prompt.")

(defun my/treesit-install-langs ()
  "Build the missing grammars of `my/treesit-langs' at treesit-auto's pinned revisions, without asking.
Signals when one failed, after trying the rest."
  ;; js-ts-mode also wants jsdoc, which treesit-auto has no recipe for
  (require 'js)
  (let ((treesit-language-source-alist (append (treesit-auto--build-treesit-source-alist)
                                               treesit-language-source-alist))
        (failed nil))
    (dolist (lang my/treesit-langs)
      (unless (treesit-ready-p lang t)
        (condition-case err
            (treesit-install-language-grammar lang)
          (error (push lang failed)
                 (message "tree-sitter: building %s failed: %s" lang (error-message-string err))))))
    (when failed
      (error "tree-sitter: building %s failed" (nreverse failed)))))

;; mason's bin dir is on PATH only inside nvim; ahead of /usr/bin so rust-analyzer is not the rustup proxy
(let ((mason-bin (expand-file-name "nvim/mason/bin" (or (getenv "XDG_DATA_HOME") "~/.local/share"))))
  (when (file-directory-p mason-bin)
    (add-to-list 'exec-path mason-bin)
    (setenv "PATH" (concat mason-bin path-separator (getenv "PATH")))))

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
          bash-ts-mode sh-mode css-ts-mode html-mode html-ts-mode
          json-ts-mode yaml-ts-mode lua-ts-mode go-ts-mode
          ruby-ts-mode ruby-mode markdown-mode gfm-mode
          latex-mode tex-mode bibtex-mode LaTeX-mode
          zig-mode nix-mode haskell-mode typst-ts-mode) . eglot-ensure)
  :config
  (setq eglot-autoshutdown t
        eglot-events-buffer-size 0
        eglot-extend-to-xref t
        ;; pyright exits when a watch is refused, /usr/lib/python3.x alone is ~14k dirs
        eglot-max-file-watches 50000)

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
               `(jai-mode . ("jails" "-jai_path" ,(expand-file-name "~/.jai")
                             "-jai_exe_name" "jai-linux")))

  (add-to-list 'eglot-server-programs '((markdown-mode gfm-mode) . ("marksman")))
  (add-to-list 'eglot-server-programs '(typst-ts-mode . ("tinymist")))

  ;; eglot binds default-directory to the project root before calling this
  (setq-default eglot-workspace-configuration #'my/eglot-workspace-configuration))

(use-package consult-eglot
  :commands (consult-eglot-symbols))
(use-package git-link
  :commands (git-link git-link-homepage)
  :config (setq git-link-open-in-browser t))

(use-package eldoc-box
  :hook (eglot-managed-mode . eldoc-box-hover-at-point-mode))

(use-package flymake
  :ensure nil
  :hook (prog-mode . flymake-mode)
  :config
  (setq flymake-show-diagnostics-at-end-of-line 'short
        flymake-no-changes-timeout 0.5
        flymake-wrap-around t))

(defun my/diagnostic-at-point ()
  "nvim SPC l o: show the diagnostics under the cursor."
  (interactive)
  (if-let* ((diags (flymake-diagnostics (point))))
      (message "%s" (mapconcat #'flymake-diagnostic-text diags "\n"))
    (message "No diagnostics at point")))

(use-package imenu-list
  :commands imenu-list-smart-toggle
  :config (setq imenu-list-position 'right
                imenu-list-size 30
                imenu-list-focus-after-activation nil))

(add-hook 'prog-mode-hook #'hs-minor-mode)

;; personal style only where the project has no config of its own
(defun my/formatting-args (names flag file)
  "FLAG joined to the personal FILE (configs/programming/formatting, copied beside init.el), nil when a project config is found.
NAMES is a list of file names, or a predicate on a directory, searched upward from `default-directory'."
  (unless (if (functionp names)
              (locate-dominating-file default-directory names)
            (seq-some (lambda (name) (locate-dominating-file default-directory name)) names))
    (concat flag (expand-file-name "formatting/" user-emacs-directory) file)))

(defun my/ruff-config-p (dir)
  "Non-nil when DIR holds a ruff config; ruff itself skips a pyproject.toml without [tool.ruff]."
  (or (file-exists-p (expand-file-name "ruff.toml" dir))
      (file-exists-p (expand-file-name ".ruff.toml" dir))
      (let ((pyproject (expand-file-name "pyproject.toml" dir)))
        (and (file-readable-p pyproject)
             (with-temp-buffer
               (insert-file-contents pyproject)
               (search-forward "[tool.ruff" nil t))))))

(use-package apheleia
  :init (apheleia-global-mode 1)
  :config
  ;; args go past the apheleia-npx wrapper; apheleia drops a nil
  (pcase-dolist (`(,formatter . ,form)
                 '((clang-format . (my/formatting-args '(".clang-format" "_clang-format") "--style=file:" "clang-format"))
                   (stylua . (my/formatting-args '("stylua.toml" ".stylua.toml") "--config-path=" "stylua.toml"))
                   (prettier . (my/formatting-args
                                '(".prettierrc" ".prettierrc.json" ".prettierrc.json5" ".prettierrc.yaml" ".prettierrc.yml"
                                  ".prettierrc.toml" ".prettierrc.js" ".prettierrc.cjs" ".prettierrc.mjs" ".prettierrc.ts"
                                  "prettier.config.js" "prettier.config.cjs" "prettier.config.mjs" "prettier.config.ts")
                                "--config=" "prettierrc.json"))
                   ;; the personal rustfmt.toml sets nightly-only options, which stable rustfmt ignores
                   (rustfmt . (let ((arg (my/formatting-args '("rustfmt.toml" ".rustfmt.toml") "--config-path=" "rustfmt.toml")))
                                (and arg (list "+nightly" arg))))
                   (ruff . (my/formatting-args #'my/ruff-config-p "--config=" "ruff.toml"))
                   (ruff-isort . (my/formatting-args #'my/ruff-config-p "--config=" "ruff.toml"))))
    (let* ((command (alist-get formatter apheleia-formatters))
           (program (and (listp command) (seq-position command nil (lambda (elt _) (and (stringp elt) (not (equal elt "apheleia-npx"))))))))
      (when program
        (setf (alist-get formatter apheleia-formatters)
              (append (seq-take command (1+ program)) (list form) (seq-drop command (1+ program)))))))
  (setf (alist-get 'python-mode    apheleia-mode-alist) '(ruff-isort ruff)
        (alist-get 'python-ts-mode apheleia-mode-alist) '(ruff-isort ruff))
  (dolist (m '(c-mode c-ts-mode c++-mode c++-ts-mode))
    (setf (alist-get m apheleia-mode-alist) 'clang-format))
  (setf (alist-get 'leptosfmt   apheleia-formatters) '("leptosfmt" "--stdin" "--rustfmt")
        (alist-get 'sortderives apheleia-formatters) '("sort-derives-stdout"))
  (dolist (m '(rust-mode rust-ts-mode))
    (setf (alist-get m apheleia-mode-alist) '(rustfmt sortderives)))
  ;; leptosfmt errors on plain rust
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

(use-package haskell-mode :defer t)
(use-package zig-mode     :defer t)
(use-package nix-mode     :defer t)
(use-package typst-ts-mode :defer t)
(use-package just-mode    :mode "[Jj]ustfile\\'")

(use-package markdown-mode
  :mode ("\\.md\\'" . gfm-mode)
  :config (setq markdown-fontify-code-blocks-natively t))

(use-package emmet-mode
  :commands emmet-wrap-with-markup)

(use-package org
  :ensure nil
  :defer t
  :config
  (setq org-directory "~/orgfiles/"
        org-default-notes-file (expand-file-name "refile.org" org-directory)
        org-agenda-files (when (file-directory-p org-directory)
                           (directory-files-recursively org-directory "\\.org\\'"))))

(use-package jai-mode
  :vc (:url "https://github.com/elp-revive/jai-mode" :rev :newest)
  :mode "\\.jai\\'"
  :hook (jai-mode . eglot-ensure))

;; nvim's spellfile, so zg in either editor feeds one list
(defconst my/spell-words (expand-file-name "~/.config/nvim/spell/en.utf-8.add"))
(defconst my/spell-dictionary "en_US")

(setq ispell-program-name "hunspell"
      ispell-dictionary my/spell-dictionary
      ispell-personal-dictionary my/spell-words
      flyspell-issue-message-flag nil
      flyspell-mark-duplications-flag nil)

(defvar my/spell-available 'unknown
  "Whether hunspell and its dictionary exist, probed once on the first prose buffer.")

(defun my/spell-available-p ()
  "Non-nil when spell checking can run; says once what is missing otherwise."
  (when (eq my/spell-available 'unknown)
    (setq my/spell-available
          (and (executable-find ispell-program-name)
               (progn (require 'ispell)
                      ;; signals when hunspell has no dictionary at all
                      (ignore-errors (ispell-find-hunspell-dictionaries))
                      (assoc my/spell-dictionary ispell-hunspell-dict-paths-alist))
               t))
    (unless my/spell-available
      (message "spell: no hunspell %s dictionary (pacman -S hunspell-en_us), spell check off"
               my/spell-dictionary)))
  my/spell-available)

(defun my/spell-lenient-p ()
  "Skip identifiers written into prose: a digit, an underscore or a capital past the first letter.
Like nvim's spelloptions=camel, GitHub or LaTeX is never flagged; whole identifiers are skipped, not split."
  (let ((case-fold-search nil)
        (word (thing-at-point 'symbol t)))
    (not (and word (string-match-p "[0-9_]\\|.[[:upper:]]" word)))))

(defun my/spell-lenient ()
  "Chain `my/spell-lenient-p' in front of the mode's own word predicate (markdown skips code, tex commands)."
  (when flyspell-mode
    (if flyspell-generic-check-word-predicate
        (add-function :before-while (local 'flyspell-generic-check-word-predicate) #'my/spell-lenient-p)
      (setq-local flyspell-generic-check-word-predicate #'my/spell-lenient-p))))

(add-hook 'flyspell-mode-hook #'my/spell-lenient)

(defun my/spell-add-word ()
  "vim zg: add the word under the cursor to the shared spellfile."
  (interactive)
  (let ((word (or (thing-at-point 'word t) (user-error "No word at point"))))
    (ispell-accept-buffer-local-defs)
    (ispell-send-string (concat "*" word "\n"))
    (ispell-send-string "#\n")
    (when (bound-and-true-p flyspell-mode) (flyspell-word))
    (message "spell: added %s" word)))

(defun my/prose-setup ()
  "nvim prose filetypes: hard wrap at 100 columns and spell check."
  (setq-local fill-column 100)
  (auto-fill-mode 1)
  (when (my/spell-available-p) (flyspell-mode 1)))

(dolist (hook '(markdown-mode-hook org-mode-hook LaTeX-mode-hook plain-TeX-mode-hook
                rst-mode-hook git-commit-setup-hook))
  (add-hook hook #'my/prose-setup))
(defun my/prose-setup-plain-text ()
  "Plain text only: yaml and other modes derive from text-mode too."
  (when (eq major-mode 'text-mode) (my/prose-setup)))
(add-hook 'text-mode-hook #'my/prose-setup-plain-text)

(use-package code-cells
  :hook ((python-mode python-ts-mode markdown-mode) . code-cells-mode-maybe))

(provide 'lang)
;;; lang.el ends here
