;;; core.el --- editor defaults -*- lexical-binding: t; -*-
;; Mirrors nvim lua/options.lua. Built-in Emacs only, no packages.

(set-language-environment "UTF-8")
(prefer-coding-system 'utf-8)
(setq shell-file-name "/usr/bin/zsh")

;;;; runtime state ----------------------------------------------------------
;; user-emacs-directory is a symlink into the git repo, so every file Emacs
;; writes at runtime would show up as repo noise. Point them all at ~/.cache.

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

;; no swap/backup/lock clutter (nvim: noswapfile, nobackup, noundofile)
(setq make-backup-files nil
      auto-save-default nil
      create-lockfiles nil)

;; restore cursor position, remember recent files and minibuffer history
(save-place-mode 1)
(recentf-mode 1)
(setq recentf-max-saved-items 200)
(savehist-mode 1)

;;;; files ------------------------------------------------------------------

(setq-default vc-follow-symlinks t)

;; autoread (nvim: autoread + checktime)
(setq global-auto-revert-non-file-buffers t
      auto-revert-verbose nil)
(global-auto-revert-mode 1)

;; create missing parent directories on save
(add-hook 'before-save-hook
          (lambda ()
            (when buffer-file-name
              (make-directory (file-name-directory buffer-file-name) t))))

;;;; editing ----------------------------------------------------------------

;; indent: 4 spaces, expandtab
(setq-default indent-tabs-mode nil
              tab-width 4
              standard-indent 4)
(setq backward-delete-char-untabify-method 'hungry)

;; smartcase search (nvim: ignorecase + smartcase)
(setq case-fold-search t)

;; parens + autopairs (nvim: mini.pairs, matchparen)
(show-paren-mode 1)
(setq show-paren-delay 0)
(electric-pair-mode 1)

;;;; display ----------------------------------------------------------------

;; number + relativenumber, with numbertoggle: absolute in insert, relative else
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

;; clipboard = unnamedplus; plain line scroll (pixel-precision lags on 4k + big font)
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

;;;; projects ---------------------------------------------------------------

(with-eval-after-load 'project
  (setq project-vc-extra-root-markers '(".project-root" "Cargo.toml" "package.json")))

(defun my/projects-dired ()
  "Buffer to land in at startup and on a new tab: ~/projects in dired."
  (dired-noselect "~/projects/"))

(provide 'core)
;;; core.el ends here
