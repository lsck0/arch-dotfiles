;;; ui.el --- theme, bars, visual aids -*- lexical-binding: t; -*-

;;;; theme + font -----------------------------------------------------------

; ; Follows the desktop theme instead of pinning one palette.
(defconst my/system-theme-file (expand-file-name "~/.cache/wal/nvim_theme"))

(defconst my/system-theme-alist
  '(("ayu-dark"       . doom-ayu-dark)
    ("ayu-light"      . doom-ayu-light)
    ("ayu-mirage"     . doom-ayu-mirage)
    ("dracula"        . doom-dracula)
    ("gruvbox-dark"   . doom-gruvbox)
    ("nord"           . doom-nord)
    ("one-dark"       . doom-one)
    ("solarized-dawn" . doom-solarized-light)
    ("tokyo-night"    . doom-tokyo-night))
  "Theme basenames in themes/ that ship a doom-themes equivalent.
Names missing here (catppuccin-*, night-owl, void, \"pywal\") fall back to
the generated doom-pywal theme.")

(defun my/system-theme ()
  "Return the doom theme symbol matching the desktop's current theme."
  (let ((name (and (file-readable-p my/system-theme-file)
                   (string-trim
                    (with-temp-buffer
                      (insert-file-contents my/system-theme-file)
                      (buffer-string))))))
    (or (cdr (assoc name my/system-theme-alist)) 'doom-pywal)))

(defun my/apply-system-theme ()
  "Load the theme matching the desktop's, replacing whatever is enabled.
Called at startup and again by switch-wallpaper.sh over emacsclient, so open
frames recolour on a theme switch exactly as a fresh launch would."
  (interactive)
  (mapc #'disable-theme custom-enabled-themes)
  (unless (ignore-errors (load-theme (my/system-theme) t))
    (load-theme 'doom-one t)))

(use-package doom-themes
  :config
  (setq doom-themes-enable-bold t
        doom-themes-enable-italic t)
  ;; where generate-editor-themes.sh writes doom-pywal-theme.el
  (add-to-list 'custom-theme-load-path
               (expand-file-name "themes/" user-emacs-directory))
  (my/apply-system-theme)
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

; ; Native tab-bar tabs are the tmux-window / nvim-tab equivalent.
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
