;;; ui.el -*- lexical-binding: t; -*-
;; Theme, modeline, tabs, indent guides, icons.

;; ayu (doom-ayu-{dark,mirage,light}); oxocarbon also bundled if you switch back
(use-package doom-themes
  :config
  (setq doom-themes-enable-bold t
        doom-themes-enable-italic t)
  (unless (ignore-errors (load-theme 'doom-ayu-dark t))
    (load-theme 'doom-one t))
  (doom-themes-org-config))

;; 0xProto everywhere, 22pt for the 4k panel (matches nvim guifont h22)
(set-face-attribute 'default nil :family "0xProto Nerd Font" :height 220)
(set-face-attribute 'fixed-pitch nil :family "0xProto Nerd Font" :height 220)
(set-face-attribute 'variable-pitch nil :family "0xProto Nerd Font" :height 220)

(use-package nerd-icons)

;; lualine -> doom-modeline
(use-package doom-modeline
  :init (doom-modeline-mode 1)
  :config
  (setq doom-modeline-height 28
        doom-modeline-buffer-encoding nil
        doom-modeline-icon t))

;; native tab pages = vim :tabn (M-1..5 / M-c / M-x). centaur shows buffers below
(setq tab-bar-show 1
      tab-bar-new-tab-choice (lambda () (get-buffer-create "*dashboard*"))
      tab-bar-tab-hints t
      tab-bar-close-button-show nil
      tab-bar-new-button-show nil)
(tab-bar-mode 1)

;; barbar -> centaur-tabs (buffer tabs along the top)
(use-package centaur-tabs
  :init (setq centaur-tabs-set-bar 'under
              x-underline-at-descent-line t
              centaur-tabs-style "bar"
              centaur-tabs-set-icons t
              centaur-tabs-set-modified-marker t
              centaur-tabs-modified-marker "●"
              centaur-tabs-cycle-scope 'tabs)
  :config
  (centaur-tabs-mode 1)
  (centaur-tabs-headline-match))

;; indent-blankline -> indent-bars
(use-package indent-bars
  :hook ((prog-mode . indent-bars-mode))
  :config
  (setq indent-bars-treesit-support t
        indent-bars-no-descend-string t
        indent-bars-width-frac 0.15))

;; rainbow-delimiters
(use-package rainbow-delimiters
  :hook (prog-mode . rainbow-delimiters-mode))

;; nvim-colorizer -> rainbow-mode (inline #rrggbb swatches)
(use-package rainbow-mode
  :hook (prog-mode . rainbow-mode))

;; hl-todo (todo-comments.nvim)
(use-package hl-todo
  :hook (prog-mode . hl-todo-mode)
  :config
  (setq hl-todo-keyword-faces
        '(("TODO" . "#ff7eb6") ("FIXME" . "#ee5396")
          ("HACK" . "#ffe97b") ("NOTE" . "#33b1ff"))))

;; zen-mode / twilight -> writeroom + focus
(use-package writeroom-mode :commands writeroom-mode)

;; cursorword (mini.cursorword) -> highlight symbol at point
(use-package highlight-thing
  :hook (prog-mode . highlight-thing-mode)
  :config (setq highlight-thing-delay-seconds 0.3
                highlight-thing-case-sensitive-p t))

;; snacks dashboard -> dashboard (landing page + project selector)
(use-package dashboard
  :init (dashboard-setup-startup-hook)
  :config
  (setq dashboard-banner-logo-title nil
        ;; official GNU Emacs logo image
        dashboard-startup-banner 'official
        dashboard-center-content t
        dashboard-vertically-center-content t
        dashboard-icon-type 'nerd-icons
        dashboard-display-icons-p t
        dashboard-set-heading-icons t
        dashboard-set-file-icons t
        dashboard-set-navigator t
        dashboard-set-footer t
        dashboard-footer-icon (nerd-icons-faicon "nf-fa-coffee" :face 'dashboard-footer)
        dashboard-projects-backend 'project-el
        dashboard-projects-switch-function #'project-switch-project
        dashboard-items '((projects . 6) (recents . 6) (bookmarks . 4))
        dashboard-item-shortcuts '((projects . "p") (recents . "r") (bookmarks . "m"))
        ;; clickable row: f find · g grep · e tree · g magit · config
        dashboard-navigator-buttons
        `(((,(nerd-icons-faicon "nf-fa-search") " Find file" "" (lambda (&rest _) (my/find-files)))
           (,(nerd-icons-faicon "nf-fa-folder") " Projects" "" (lambda (&rest _) (project-switch-project)))
           (,(nerd-icons-octicon "nf-oct-git_branch") " Magit" "" (lambda (&rest _) (magit-status)))
           (,(nerd-icons-faicon "nf-fa-cog") " Config" "" (lambda (&rest _) (my/find-files-dotfiles))))))
  ;; open dashboard, not *scratch*, at startup (snacks keys live in keys.el)
  (setq initial-buffer-choice (lambda () (get-buffer-create dashboard-buffer-name))))

(provide 'ui)
;;; ui.el ends here
