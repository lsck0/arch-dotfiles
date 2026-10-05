;;; core.el --- editor defaults -*- lexical-binding: t; -*-

(set-language-environment "UTF-8")
(prefer-coding-system 'utf-8)
(setq shell-file-name "/usr/bin/zsh")

;; early-init.el sets these (and toggle-font.sh rewrites them there); emacs --batch -l init.el never reads
;; it, so declare neutral fallbacks rather than a second copy of the real values that could drift
(defvar my/font-family "monospace")
(defvar my/font-size 16)

;;;; runtime state ----------------------------------------------------------

(defvar my/cache-dir
  (expand-file-name "emacs/" (or (getenv "XDG_CACHE_HOME") "~/.cache/"))
  "Directory for Emacs runtime state, kept out of the dotfiles repo.")

(make-directory my/cache-dir t)

(defun my/cache (name)
  "Absolute path to NAME inside `my/cache-dir'."
  (expand-file-name name my/cache-dir))

(setq auto-save-list-file-prefix   (my/cache "auto-save-")
      save-place-file              (my/cache "places")
      recentf-save-file            (my/cache "recentf")
      savehist-file                (my/cache "history")
      project-list-file            (my/cache "projects")
      transient-history-file       (my/cache "transient-history")
      transient-levels-file        (my/cache "transient-levels")
      transient-values-file        (my/cache "transient-values")
      tramp-persistency-file-name  (my/cache "tramp")
      url-configuration-directory  (my/cache "url/"))

;; no swap/backup/lock clutter
(setq make-backup-files nil
      auto-save-default nil
      create-lockfiles nil)

(save-place-mode 1)
(recentf-mode 1)
(setq recentf-max-saved-items 200)
(savehist-mode 1)

;;;; files ------------------------------------------------------------------

(setq-default vc-follow-symlinks t)

;; autoread
(setq global-auto-revert-non-file-buffers t
      auto-revert-verbose nil)
(global-auto-revert-mode 1)

;; create missing parent directories on save
(add-hook 'before-save-hook
          (lambda ()
            (when buffer-file-name
              (make-directory (file-name-directory buffer-file-name) t))))

;;;; editing ----------------------------------------------------------------

(setq-default indent-tabs-mode nil
              tab-width 4
              standard-indent 4)
(setq backward-delete-char-untabify-method 'hungry)

;; smartcase search
(setq case-fold-search t)

(show-paren-mode 1)
(setq show-paren-delay 0)
(electric-pair-mode 1)

;;;; display ----------------------------------------------------------------

;; absolute line numbers in insert, relative else
(setq display-line-numbers-type 'relative)
(global-display-line-numbers-mode 1)
(add-hook 'evil-insert-state-entry-hook (lambda () (setq display-line-numbers t)))
(add-hook 'evil-insert-state-exit-hook  (lambda () (setq display-line-numbers 'relative)))

(global-hl-line-mode 1)                 ; cursorline

;; scrolloff, nowrap, colorcolumn 120
(setq scroll-margin 8
      scroll-conservatively 101
      scroll-preserve-screen-position t)
(setq-default truncate-lines t
              fill-column 120)
(setq display-fill-column-indicator-character ?▕)
(global-display-fill-column-indicator-mode 1)

;; buffers that are not code: no gutter decoration
(dolist (hook '(term-mode-hook eat-mode-hook eshell-mode-hook dired-mode-hook))
  (add-hook hook (lambda ()
                   (display-line-numbers-mode -1)
                   (display-fill-column-indicator-mode -1))))

;;;; input ------------------------------------------------------------------

;; plain line scroll: pixel precision lags on 4k + big font
(setq select-enable-clipboard t
      mouse-wheel-progressive-speed nil
      mouse-wheel-follow-mouse t
      mouse-wheel-scroll-amount '(3 ((shift) . 1) ((control) . nil)))

(setq echo-keystrokes 0.1
      ring-bell-function 'ignore)
(setopt use-short-answers t)

;; minibuffer hygiene (vertico/consult assume these)
(setq enable-recursive-minibuffers t
      read-extended-command-predicate #'command-completion-default-include-p
      minibuffer-prompt-properties
      '(read-only t cursor-intangible t face minibuffer-prompt))
(add-hook 'minibuffer-setup-hook #'cursor-intangible-mode)

;;;; performance ------------------------------------------------------------

;; stop font-cache compaction (nerd-icons), defer fontification while scrolling
(setq inhibit-compacting-font-caches t
      redisplay-skip-fontification-on-input t
      fast-but-imprecise-scrolling t
      jit-lock-defer-time 0
      auto-window-vscroll nil
      bidi-inhibit-bpa t)
(global-so-long-mode 1)

;;;; server -----------------------------------------------------------------

;; zathura's backward search (scripts/synctex-edit.sh) and switch-wallpaper.sh reach Emacs over emacsclient
(require 'server)
(unless (or noninteractive (server-running-p))
  (server-start))

;;;; projects ---------------------------------------------------------------

(with-eval-after-load 'project
  (setq project-vc-extra-root-markers '(".project-root" "Cargo.toml" "package.json")))

(defconst my/projects-default-dirs '(("~/projects/" . 10))
  "Search dirs as (PATH . DEPTH) when ~/.config/tms/config.toml has none.")

(defconst my/projects-exclude '("elpa" "node_modules" ".cargo" "vendor" "target")
  "Vendored repos are not projects; mirrors the --exclude list in scripts/hms.sh.")

(defun my/projects-search-dirs ()
  "The [[search_dirs]] of ~/.config/tms/config.toml as (PATH . DEPTH), so the picker and hms agree."
  (let ((file (expand-file-name "~/.config/tms/config.toml"))
        dirs)
    (when (file-readable-p file)
      (with-temp-buffer
        (insert-file-contents file)
        (while (re-search-forward (concat "^[ \t]*\\(?:\\(\\[\\[search_dirs]]\\)"
                                          "\\|path[ \t]*=[ \t]*\"\\([^\"]*\\)\""
                                          "\\|depth[ \t]*=[ \t]*\\([0-9]+\\)\\)")
                                  nil t)
          (cond ((match-beginning 1) (push (cons nil 10) dirs))
                ((not dirs))
                ((match-beginning 2) (setcar (car dirs) (match-string 2)))
                (t (setcdr (car dirs) (string-to-number (match-string 3))))))))
    (or (seq-filter #'car (nreverse dirs)) my/projects-default-dirs)))

(defun my/project-checkout-p (git)
  "Whether GIT, a .git entry, marks a checkout: any .git directory, or a .git file pointing into <gitdir>/worktrees/.
That is how bare-repo layouts show up, while submodules and the bare layout's own root (gitdir: ./.bare) do not."
  (or (file-directory-p git)
      (with-temp-buffer
        (ignore-errors (insert-file-contents git nil 0 4096))
        (looking-at-p "gitdir: .*/worktrees/[^/\n]+/?$"))))

(defun my/projects-list ()
  "Every git checkout and worktree under the tms search dirs as (DISPLAY . PATH), sorted by DISPLAY."
  (unless (executable-find "fd") (user-error "projects: fd is not installed"))
  (let (out)
    (pcase-dolist (`(,root . ,depth) (my/projects-search-dirs))
      (setq root (file-name-as-directory (expand-file-name root)))
      (when (file-directory-p root)
        ;; --type f too: a worktree has a .git file, not a directory
        (dolist (git (apply #'process-lines-ignore-status
                            "fd" "--hidden" "--no-ignore" "--type" "d" "--type" "f"
                            "--max-depth" (number-to-string depth)
                            (append (mapcan (lambda (ex) (list "--exclude" ex)) my/projects-exclude)
                                    (list "^\\.git$" root))))
          (let* ((dir (file-name-directory (directory-file-name git)))
                 (rel (directory-file-name (string-remove-prefix root dir))))
            (unless (or (rassoc dir out) (not (my/project-checkout-p git)))
              (push (cons (if (string-empty-p rel) dir rel) dir) out))))))
    (sort out (lambda (a b) (string< (car a) (car b))))))

(defun my/project-open (dir)
  "nvim tcd: move to project DIR, re-rooting the sidebar there, then find a file in it."
  (my/tree-reroot dir)
  (let ((default-directory dir))
    (my/find-files)))

(defun my/project-pick ()
  "nvim SPC f p: the repo list hms and tms show, not only projects visited before."
  (interactive)
  (let* ((items (or (my/projects-list)
                    (user-error "projects: no git repos under the tms search dirs")))
         (pick (completing-read "Projects: " items nil t)))
    (my/project-open (cdr (assoc pick items)))))

(provide 'core)
;;; core.el ends here
