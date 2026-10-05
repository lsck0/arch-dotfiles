;;; ui.el --- theme, bars, visual aids -*- lexical-binding: t; -*-

;;;; theme + font -----------------------------------------------------------

;; follows the desktop theme
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
  "Theme names from configs/themes with a doom-themes equivalent; the rest use doom-pywal.")

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

;; family/size from early-init.el so the first frame is right
(dolist (face '(default fixed-pitch variable-pitch))
  (set-face-attribute face nil
                      :family my/font-family
                      :height (* 10 my/font-size)))

(use-package nerd-icons)

;;;; bottom bar -------------------------------------------------------------

(use-package doom-modeline
  :init (doom-modeline-mode 1)
  :config
  (setq doom-modeline-height 25
        doom-modeline-buffer-file-name-style 'relative-to-project
        doom-modeline-buffer-encoding nil
        doom-modeline-icon t))

;;;; top bar ----------------------------------------------------------------

;; tab-bar tabs = tmux windows / nvim tabs
(setq tab-bar-show 1
      tab-bar-new-tab-choice "*scratch*"  ; nvim :tabnew: an empty buffer, not a file browser
      tab-bar-tab-hints t                 ; number each tab
      tab-bar-close-button-show nil
      tab-bar-new-button-show nil
      tab-bar-format '(tab-bar-format-tabs tab-bar-separator))
(tab-bar-mode 1)

;; doom-themes skips tab labels; inherit so theme switches carry over
(set-face-attribute 'tab-bar-tab nil
                    :inherit 'tab-line-tab-current :box nil :weight 'bold)
(set-face-attribute 'tab-bar-tab-inactive nil
                    :inherit 'tab-line-tab-inactive :box nil :weight 'normal)

;;;; visual aids ------------------------------------------------------------

(use-package indent-bars
  :hook (prog-mode . indent-bars-mode)
  :config
  (setq indent-bars-treesit-support t
        indent-bars-no-descend-string t
        indent-bars-width-frac 0.15))

(use-package rainbow-delimiters
  :hook (prog-mode . rainbow-delimiters-mode))

(use-package hl-todo
  :hook (prog-mode . hl-todo-mode)
  :config
  (setq hl-todo-keyword-faces
        '(("TODO" . "#ff7eb6") ("FIXME" . "#ee5396")
          ("HACK" . "#ffe97b") ("NOTE" . "#33b1ff"))))

;; sticky header with the enclosing definition
(use-package topsy
  :hook (prog-mode . topsy-mode))

;; empty *scratch* in the main window, the dirvish sidebar already shows the files
(setq initial-buffer-choice t)

;; highlight on yank, like nvim's TextYankPost vim.hl.on_yank
(defun my/yank-pulse (beg end &rest _)
  (pulse-momentary-highlight-region beg end))
(with-eval-after-load 'evil
  (advice-add 'evil-yank :after #'my/yank-pulse))

(provide 'ui)
;;; ui.el ends here
