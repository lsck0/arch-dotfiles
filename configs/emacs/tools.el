;;; tools.el -*- lexical-binding: t; -*-
;; which-key, snippets, harpoon, undotree, terminal, misc.

;; which-key is builtin in Emacs 30
(use-package which-key
  :ensure nil
  :init (which-key-mode 1)
  :config (setq which-key-idle-delay 0.2))   ; nvim timeoutlen = 200

;; LuaSnip -> yasnippet
(use-package yasnippet
  :init (yas-global-mode 1))
(use-package yasnippet-snippets :after yasnippet)

;; custom snippets ported 1:1 from nvim lua/snippets.lua
(require 'cl-lib)
(with-eval-after-load 'yasnippet
  (let* ((long  (make-string 117 ?─))
         (short (make-string 57 ?─))
         ;; one comment-style -> the two banner snippets (banner + smallbanner)
         (banner (lambda (open line mid close)
                   (cl-flet ((tpl (dashes)
                               (concat "\n" open
                                       "\n" line " " dashes
                                       "\n" mid "$1"
                                       "\n" line " " dashes
                                       "\n" close "\n")))
                     (list (list "banner"      (tpl long)  "banner")
                           (list "smallbanner" (tpl short) "smallbanner"))))))
    ;; (style . modes); style = (open line mid close)
    (dolist (group `(((  "/*" " *" " * " " */") .
                      (c-mode c-ts-mode c++-mode c++-ts-mode
                       js-mode js-ts-mode typescript-ts-mode tsx-ts-mode))
                     (( "#" "#" "# " "#") . (python-mode python-ts-mode))
                     (( "%" "%" "% " "%") . (latex-mode LaTeX-mode tex-mode plain-tex-mode))
                     (( "--" "--" "-- " "--") . (lua-mode lua-ts-mode))))
      (let ((snips (apply banner (car group))))
        (dolist (m (cdr group))
          (yas-define-snippets m snips)))))

  ;; rust struct/enum
  (let ((rust-snips
         '(("struct" "#[derive(Debug, Clone)]\npub struct ${1:Name} {\n    $0\n}" "struct")
           ("enum"   "#[derive(Debug, Clone)]\npub enum ${1:Name} {\n    $0\n}" "enum"))))
    (dolist (m '(rust-mode rust-ts-mode))
      (yas-define-snippets m rust-snips))))

;; winshift.nvim -> ace-window (swap/move windows)
(use-package ace-window
  :commands (ace-window aw-swap-window)
  :config (setq aw-keys '(?a ?s ?d ?f ?g ?h ?j ?k ?l)))

;; kulala.nvim (http client) -> restclient
(use-package restclient
  :mode ("\\.http\\'" . restclient-mode))

;; harpoon (ThePrimeagen/harpoon)
(use-package harpoon)

;; undotree (jiaoshijie/undotree) -> vundo
(use-package vundo
  :commands vundo
  :config (setq vundo-glyph-alist vundo-unicode-symbols))

;; spectre (search/replace across project)
(use-package wgrep)   ; edit grep buffers in place == spectre apply

;; terminal (nvim :terminal) -> eat, pure elisp, no compile.
;; nvim runs terminals inside tmux for tab/window multiplexing; here each
;; terminal opens in its own tab-bar tab (M-t below), so M-1..5 / M-c / M-x
;; switch/spawn/close them exactly like tmux windows.
(use-package eat
  :commands (eat eat-other-window my/eat-tab)
  :config (setq eat-kill-buffer-on-exit t))

(defun my/eat-tab ()
  "Open a terminal in its own tab-bar tab (tmux-window feel).
Reuses an existing terminal tab if its eat buffer is still alive,
otherwise spawns a fresh one. nvim M-t parity."
  (interactive)
  (require 'eat)
  (let ((default-directory (or (and (project-current)
                                    (project-root (project-current)))
                               default-directory)))
    (tab-bar-new-tab)
    (let ((eat-kill-buffer-on-exit t))
      (eat))
    ;; name the tab after the shell so it's findable in the tab list
    (tab-bar-rename-tab "term")))

;; pomo.nvim -> pomm / org timers; lightweight tea-timer
(use-package tmr :commands (tmr tmr-with-description))

;; orgmode (built-in) basic agenda paths
(use-package org
  :ensure nil
  :config
  (setq org-directory "~/orgfiles"
        org-agenda-files '("~/orgfiles")
        org-default-notes-file "~/orgfiles/refile.org"))

;; csvview.nvim
(use-package csv-mode :mode "\\.csv\\'")

;; cloak.nvim (.env masking)
(use-package redacted :commands redacted-mode)

;; popper (Doom-style popup management): compile / help / flymake / messages get
;; herded into a dismissable bottom stack. C-` toggle latest, M-` cycle, C-M-`
;; promote/demote a window to/from popup. eat terminals stay out (they own tabs).
(use-package popper
  :demand t                              ; load at startup so it catches popups
  :bind (("C-`"   . popper-toggle)
         ("M-`"   . popper-cycle)
         ("C-M-`" . popper-toggle-type))
  :init
  (setq popper-reference-buffers
        '("\\*Messages\\*"
          "\\*Warnings\\*"
          "Output\\*$"
          "\\*Async Shell Command\\*"
          "\\*compilation\\*"
          "\\*Compile-Log\\*"
          compilation-mode
          help-mode
          helpful-mode
          "\\*eldoc\\*"
          flymake-diagnostics-buffer-mode
          "\\*Flymake diagnostics.*\\*"))
  :config                                ; modes activate after the package loads
  (popper-mode 1)
  (popper-echo-mode 1))

;; helpful (Doom): richer C-h f/v/k buffers (source, refs, callers, examples)
(use-package helpful
  :bind (([remap describe-function] . helpful-callable)
         ([remap describe-variable] . helpful-variable)
         ([remap describe-key]      . helpful-key)
         ([remap describe-command]  . helpful-command)
         ([remap describe-symbol]   . helpful-symbol)))

;; persp workspaces (Doom SPC TAB): per-project window layouts. SPC TAB keys
;; live in keys.el. Pairs with harpoon for fast project-local navigation.
(use-package perspective
  :init
  (setq persp-suppress-no-prefix-key-warning t
        persp-initial-frame-name "main")
  :config (persp-mode 1))

;; ws-butler: trim trailing whitespace only on lines you actually edited, so it
;; never blows up an unrelated diff (unlike a blanket delete-trailing-whitespace)
(use-package ws-butler
  :hook ((prog-mode . ws-butler-mode)
         (text-mode . ws-butler-mode)))

(provide 'tools)
;;; tools.el ends here
