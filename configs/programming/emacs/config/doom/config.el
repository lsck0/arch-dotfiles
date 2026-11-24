;;; $DOOMDIR/config.el -*- lexical-binding: t; -*-

;;; theme

(defconst my/wal-dir (expand-file-name "wal/" (or (getenv "XDG_CACHE_HOME") "~/.cache"))
  "Where the emacs module's theme verb writes the palette theme and the font.")
(defconst my/theme 'doom-pywal)
(defconst my/font-file (expand-file-name "emacs-font.el" my/wal-dir))

(add-to-list 'custom-theme-load-path my/wal-dir)
(load my/font-file t t)
(when (locate-file (format "%s-theme.el" my/theme) (list my/wal-dir))
  (setq doom-theme my/theme))

(defun my/theme-reload ()
  "Load the palette theme and font again; the emacs module's theme verb calls it over emacsclient."
  (load my/font-file t t)
  (mapc #'disable-theme custom-enabled-themes)
  (setq doom-theme my/theme)
  (load-theme doom-theme t)
  (doom/reload-font))

;;; format

(defconst my/formatting-dir (expand-file-name "formatting/" doom-user-dir)
  "configs/programming/formatting, copied here by the emacs module: the fallback configs nvim's conform passes too.")

(defconst my/prettier-configs
  '(".prettierrc" ".prettierrc.json" ".prettierrc.json5" ".prettierrc.yaml" ".prettierrc.yml" ".prettierrc.toml"
    ".prettierrc.js" ".prettierrc.cjs" ".prettierrc.mjs" ".prettierrc.ts"
    "prettier.config.js" "prettier.config.cjs" "prettier.config.mjs" "prettier.config.ts"))

(defun my/formatting-arg (names flag file)
  "FLAG joined to the personal FILE in `my/formatting-dir', nil when a project config is found.
NAMES is a list of file names, or a predicate on a directory, searched upward from `default-directory'."
  (unless (if (functionp names)
              (locate-dominating-file default-directory names)
            (seq-some (lambda (name) (locate-dominating-file default-directory name)) names))
    (concat flag my/formatting-dir file)))

(defun my/ruff-config-p (dir)
  "Non-nil when DIR holds a ruff config; ruff itself skips a pyproject.toml without [tool.ruff]."
  (or (file-exists-p (expand-file-name "ruff.toml" dir))
      (file-exists-p (expand-file-name ".ruff.toml" dir))
      (let ((pyproject (expand-file-name "pyproject.toml" dir)))
        (and (file-readable-p pyproject)
             (with-temp-buffer
               (insert-file-contents pyproject)
               (search-forward "[tool.ruff" nil t))))))

(defconst my/formatting-args
  '(("clang-format" . (my/formatting-arg '(".clang-format" "_clang-format") "--style=file:" "clang-format"))
    ("stylua"       . (my/formatting-arg '("stylua.toml" ".stylua.toml") "--config-path=" "stylua.toml"))
    ("prettier"     . (my/formatting-arg my/prettier-configs "--config=" "prettierrc.json"))
    ;; the personal rustfmt.toml is nightly-only; a project's own config runs on its toolchain
    ("rustfmt"      . (when-let* ((arg (my/formatting-arg '("rustfmt.toml" ".rustfmt.toml") "--config-path=" "rustfmt.toml")))
                        (list "+nightly" arg)))
    ("ruff"         . (my/formatting-arg #'my/ruff-config-p "--config=" "ruff.toml")))
  "Per formatter program, the form apheleia evaluates into its personal config argument, placed after the program.")

(defun my/cargo-toml-mentions-p (word)
  (when-let* ((root (locate-dominating-file default-directory "Cargo.toml")))
    (with-temp-buffer
      (insert-file-contents (expand-file-name "Cargo.toml" root))
      (search-forward word nil t))))

(defun my/rust-leptos-formatters-h ()
  (when (my/cargo-toml-mentions-p "leptos")
    (setq-local +format-with '(rustfmt leptosfmt sortderives))))

(add-hook! '(rust-mode-hook rust-ts-mode-hook rustic-mode-hook) #'my/rust-leptos-formatters-h)

;; nvim formats tex on save with latexindent too
(setq +format-on-save-disabled-modes
      (cl-set-difference +format-on-save-disabled-modes '(tex-mode latex-mode LaTeX-mode)))

(after! apheleia
  ;; the personal configs set the indent; doom's --style and --tab-width overrides would win over them
  (setq apheleia-formatters-respect-indent-level nil)
  (pcase-dolist (`(,formatter . ,command) apheleia-formatters)
    (when-let* (((listp command))
                (program (seq-position command nil (lambda (elt _) (and (stringp elt) (not (equal elt "apheleia-npx"))))))
                (form (cdr (assoc (nth program command) my/formatting-args))))
      (setf (alist-get formatter apheleia-formatters)
            (append (seq-take command (1+ program)) (list form) (seq-drop command (1+ program))))))
  (setf (alist-get 'sortderives apheleia-formatters) (list (expand-file-name "sort-derives-stdout.nu" my/formatting-dir))
        (alist-get 'leptosfmt   apheleia-formatters) '("leptosfmt" "--stdin" "--rustfmt")
        (alist-get 'latexindent apheleia-formatters) '("latexindent" "-m" "-g" "/dev/null"))
  (dolist (mode '(python-mode python-ts-mode))           (setf (alist-get mode apheleia-mode-alist) '(ruff-isort ruff)))
  (dolist (mode '(c-mode c-ts-mode c++-mode c++-ts-mode)) (setf (alist-get mode apheleia-mode-alist) 'clang-format))
  (dolist (mode '(rust-mode rust-ts-mode rustic-mode))   (setf (alist-get mode apheleia-mode-alist) '(rustfmt sortderives)))
  (dolist (mode '(go-mode go-ts-mode))                   (setf (alist-get mode apheleia-mode-alist) '(goimports gofumpt)))
  (dolist (mode '(sh-mode bash-ts-mode))                 (setf (alist-get mode apheleia-mode-alist) 'shfmt))
  (dolist (mode '(lua-mode lua-ts-mode))                 (setf (alist-get mode apheleia-mode-alist) 'stylua))
  (dolist (mode '(nix-mode nix-ts-mode))                 (setf (alist-get mode apheleia-mode-alist) 'nixfmt)))

;;; latex

;; sioyek is not one of doom's viewers; synctex-edit (configs/latex/sioyek) answers its inverse search over emacsclient
(setq +latex-viewers nil)

(defun my/latex-view-after-build (_output)
  "Forward search after every successful build, as vimtex does, so the pdf follows the line just edited."
  (when (buffer-live-p TeX-command-buffer)
    (with-current-buffer TeX-command-buffer (TeX-view))))

(after! tex
  (add-to-list 'TeX-view-program-list
               '("Sioyek" ("sioyek --nofocus %o"
                           (mode-io-correlate " --forward-search-file \"%b\" --forward-search-line %n"))
                 "sioyek"))
  (setf (alist-get 'output-pdf TeX-view-program-selection) '("Sioyek"))
  (add-hook 'TeX-after-compilation-finished-functions #'my/latex-view-after-build))
