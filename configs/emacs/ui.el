;;; ui.el --- theme, bars, visual aids -*- lexical-binding: t; -*-
;; Top bar  = tab-bar    (nvim barbar / tmux windows)
;; Bottom bar = doom-modeline (nvim lualine)

;;;; theme + font -----------------------------------------------------------

;; ayu dark, same palette as the nvim colorscheme
(use-package doom-themes
  :config
  (setq doom-themes-enable-bold t
        doom-themes-enable-italic t)
  (unless (ignore-errors (load-theme 'doom-ayu-dark t))
    (load-theme 'doom-one t))
  (doom-themes-org-config))

;; family/size come from early-init.el so the first frame is already correct
(dolist (face '(default fixed-pitch variable-pitch))
  (set-face-attribute face nil
                      :family my/font-family
                      :height (* 10 my/font-size)))

(use-package nerd-icons)

;;;; bottom bar -------------------------------------------------------------

;; lualine -> doom-modeline: mode, branch, diff, diagnostics, file, position
(use-package doom-modeline
  :init (doom-modeline-mode 1)
  :config
  (setq doom-modeline-height 25
        doom-modeline-buffer-file-name-style 'relative-to-project
        doom-modeline-buffer-encoding nil
        doom-modeline-icon t))

;;;; top bar ----------------------------------------------------------------

;; Native tab-bar tabs are the tmux-window / nvim-tab equivalent. M-1..5 and
;; C-q 1..5 select them, M-c/C-q c spawns, M-x/C-q x closes (see keys.el).
(setq tab-bar-show 1
      tab-bar-new-tab-choice #'my/projects-dired
      tab-bar-tab-hints t                 ; number each tab
      tab-bar-close-button-show nil
      tab-bar-new-button-show nil
      tab-bar-format '(tab-bar-format-tabs tab-bar-separator))
(tab-bar-mode 1)

;;;; visual aids ------------------------------------------------------------

;; indent-blankline -> indent-bars
(use-package indent-bars
  :hook (prog-mode . indent-bars-mode)
  :config
  (setq indent-bars-treesit-support t
        indent-bars-no-descend-string t
        indent-bars-width-frac 0.15))

(use-package rainbow-delimiters
  :hook (prog-mode . rainbow-delimiters-mode))

;; todo-comments.nvim
(use-package hl-todo
  :hook (prog-mode . hl-todo-mode)
  :config
  (setq hl-todo-keyword-faces
        '(("TODO" . "#ff7eb6") ("FIXME" . "#ee5396")
          ("HACK" . "#ffe97b") ("NOTE" . "#33b1ff"))))

;; nvim-treesitter-context -> sticky header with the enclosing definition
(use-package topsy
  :hook (prog-mode . topsy-mode))

;; Land in ~/projects instead of *scratch* (nvim/tmux both start in a project)
(setq initial-buffer-choice #'my/projects-dired)

(provide 'ui)
;;; ui.el ends here
