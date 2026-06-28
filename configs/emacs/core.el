;;; core.el -*- lexical-binding: t; -*-
;; Defaults mirroring nvim options.lua.

(set-language-environment "UTF-8")
(prefer-coding-system 'utf-8)
(setq shell-file-name "/usr/bin/zsh")
(setq-default vc-follow-symlinks t)

;; no swap/backup clutter
(setq make-backup-files nil
      auto-save-default nil
      create-lockfiles nil)

;; autoread
(setq global-auto-revert-non-file-buffers t
      auto-revert-verbose nil)
(global-auto-revert-mode 1)

;; restore cursor to last position on reopen (nvim BufReadPost cursor restore)
;; keep the runtime DB out of the (symlinked) repo -> ~/.cache
(setq save-place-file (expand-file-name "emacs/places" (or (getenv "XDG_CACHE_HOME") "~/.cache")))
(save-place-mode 1)

;; smartcase search (nvim ignorecase + smartcase)
(setq case-fold-search t)

;; mkdir on save
(add-hook 'before-save-hook
          (lambda ()
            (when buffer-file-name
              (let ((dir (file-name-directory buffer-file-name)))
                (unless (file-directory-p dir)
                  (make-directory dir t))))))

;; indent: 4 spaces, expandtab
(setq-default indent-tabs-mode nil
              tab-width 4
              standard-indent 4)
(setq backward-delete-char-untabify-method 'hungry)

;; number + relativenumber, with numbertoggle: absolute in insert, relative else
(setq display-line-numbers-type 'relative)
(global-display-line-numbers-mode 1)
(add-hook 'evil-insert-state-entry-hook
          (lambda () (setq display-line-numbers t)))
(add-hook 'evil-insert-state-exit-hook
          (lambda () (setq display-line-numbers 'relative)))
;; cursorline
(global-hl-line-mode 1)
;; scrolloff, nowrap, colorcolumn 120, signcolumn
(setq scroll-margin 8
      scroll-conservatively 101
      scroll-preserve-screen-position t)
(setq-default truncate-lines t
              fill-column 120)
(setq display-fill-column-indicator-character ?▕)
(global-display-fill-column-indicator-mode 1)
(setq whitespace-style '(face tabs trailing tab-mark)
      whitespace-display-mappings '((tab-mark ?\t [?▸ ?\t])))

(dolist (hook '(term-mode-hook eat-mode-hook eshell-mode-hook
                treemacs-mode-hook pdf-view-mode-hook dired-mode-hook))
  (add-hook hook (lambda ()
                   (display-line-numbers-mode -1)
                   (display-fill-column-indicator-mode -1))))

;; clipboard = unnamedplus, mouse
;; plain line scroll (pixel-precision is laggy on 4k + big font)
(setq select-enable-clipboard t
      mouse-wheel-progressive-speed nil
      mouse-wheel-follow-mouse t
      mouse-wheel-scroll-amount '(3 ((shift) . 1) ((control) . nil)))

;; redisplay perf: stop font-cache compaction (nerd-icons), defer fontification
(setq inhibit-compacting-font-caches t
      redisplay-skip-fontification-on-input t
      fast-but-imprecise-scrolling t
      jit-lock-defer-time 0
      auto-window-vscroll nil)

(setq echo-keystrokes 0.1)
(setopt use-short-answers t)
(setq ring-bell-function 'ignore)
(setq bidi-inhibit-bpa t)
(global-so-long-mode 1)

;; parens + autopairs
(show-paren-mode 1)
(setq show-paren-delay 0)
(electric-pair-mode 1)

(with-eval-after-load 'project
  (setq project-vc-extra-root-markers '(".project-root" "Cargo.toml" "package.json")))

(provide 'core)
;;; core.el ends here
