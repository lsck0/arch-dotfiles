;;; tools.el --- terminal, compile, windows, popups -*- lexical-binding: t; -*-

(defun my/project-root ()
  "Root of the current project, or `default-directory' outside one."
  (if-let* ((proj (project-current)))
      (project-root proj)
    default-directory))

;;;; which-key ---------------------------------------------------------------

(use-package which-key
  :ensure nil                             ; built in since Emacs 30
  :init (which-key-mode 1)
  :config (setq which-key-idle-delay 0.2)) ; nvim timeoutlen = 200

;;;; terminal ----------------------------------------------------------------

;; eat: pure elisp, no compilation step, good enough for a fallback setup.
;; Two entry points mirroring how terminals are reached in tmux:
;;   M-t   -> terminal in its own tab   (tmux new window / nvim :terminal)
;;   C-q z -> terminal popup at bottom  (tmux `bind z display-popup -E zsh`)
(use-package eat
  :commands (eat eat-other-window)
  :config (setq eat-kill-buffer-on-exit t)
  ;; terminals open typeable, like tmux
  :hook (eat-mode . evil-insert-state))

(defun my/eat-tab ()
  "Open a shell in its own tab-bar tab, rooted at the project."
  (interactive)
  (require 'eat)
  (let ((default-directory (my/project-root)))
    (tab-bar-new-tab)
    ;; ARG non-numeric = a fresh session, so every tab gets its own shell the
    ;; way every tmux window does. `eat' returns the buffer; switch explicitly
    ;; so the new tab always ends up showing it.
    (switch-to-buffer (eat nil t))
    (tab-bar-rename-tab "term")))

(defvar my/eat-popup-name "*eat-popup*"
  "Buffer name of the toggleable bottom terminal.")

(defun my/eat-popup ()
  "Toggle a shell in a window at the bottom, rooted at the project."
  (interactive)
  (require 'eat)
  (if-let* ((win (get-buffer-window my/eat-popup-name)))
      (quit-restore-window win 'bury)     ; never errors on a sole window
    (let* ((default-directory (my/project-root))
           (buf (or (get-buffer my/eat-popup-name)
                    ;; `eat-buffer-name' names it up front, so no renaming and
                    ;; no clash with the per-tab terminals above
                    (save-window-excursion
                      (let ((eat-buffer-name my/eat-popup-name))
                        (eat))))))
      (select-window (display-buffer buf))
      (evil-insert-state))))

;;;; compile -----------------------------------------------------------------
;; compile-mode.nvim: `m` compiles, output opens below (see popups).

(setq compilation-scroll-output 'first-error
      compilation-always-kill t           ; never ask before restarting a build
      compilation-ask-about-save nil      ; save modified buffers silently
      compilation-max-output-line-length nil)

;; render build output colours instead of raw escape codes
(add-hook 'compilation-filter-hook #'ansi-color-compilation-filter)

;;;; popups ------------------------------------------------------------------
;; Replaces the popper package: transient buffers get a dismissable bottom
;; window instead of stealing a split. `q` closes them (evil-collection).

(add-to-list 'display-buffer-alist
             `(,(rx bos (or "*eat-popup*" "*Warnings*" "*Messages*"
                            "*Async Shell Command*" "*eldoc*"))
               (display-buffer-reuse-window display-buffer-in-side-window)
               (side . bottom) (slot . 0) (window-height . 0.35)))

(add-to-list 'display-buffer-alist
             '((or (derived-mode . compilation-mode)
                   (derived-mode . flymake-diagnostics-buffer-mode)
                   (derived-mode . flymake-project-diagnostics-mode)
                   (derived-mode . help-mode)
                   (derived-mode . xref--xref-buffer-mode))
               (display-buffer-reuse-window display-buffer-in-side-window)
               (side . bottom) (slot . 0) (window-height . 0.35)))

;;;; windows -----------------------------------------------------------------

;; winshift.nvim -> jump/swap windows by letter
(use-package ace-window
  :commands (ace-window ace-swap-window)
  :config (setq aw-keys '(?a ?s ?d ?f ?g ?h ?j ?k ?l)
                aw-scope 'frame))

;;;; editing helpers ---------------------------------------------------------

;; undotree.nvim -> visual undo tree
(use-package vundo
  :commands vundo
  :config (setq vundo-glyph-alist vundo-unicode-symbols))

;; trim trailing whitespace only on lines actually edited, so it never
;; pollutes a diff with unrelated churn
(use-package ws-butler
  :hook ((prog-mode . ws-butler-mode)
         (text-mode . ws-butler-mode)))

(provide 'tools)
;;; tools.el ends here
