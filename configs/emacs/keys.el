;;; keys.el -*- lexical-binding: t; -*-
;; Keybindings, kept 1:1 with nvim mappings.lua. Leader = SPC.

(use-package general
  :config (general-evil-setup t))

;;;; helpers ----------------------------------------------------------------

(defun my/find-files ()
  "telescope find_files: project files, else fd in cwd."
  (interactive)
  (if (project-current)
      (project-find-file)
    (consult-fd default-directory)))

(defun my/find-files-dotfiles ()
  "telescope find_files cwd=~/projects/arch-dotfiles."
  (interactive)
  (consult-fd "~/projects/arch-dotfiles/"))

(defun my/grep-string ()
  "telescope grep_string: ripgrep for symbol at point."
  (interactive)
  (consult-ripgrep default-directory (thing-at-point 'symbol t)))

(defun my/run-macro ()
  "nvim M-q: execute macro from a register."
  (interactive)
  (evil-execute-macro 1 (evil-get-register (read-char "@register: ") t)))

;;;; non-leader global maps (nvim n/i/t/normal) -----------------------------

;; C-s save, C-c exit insert (insert map set in evil-setup)
(general-def 'global "C-s" #'save-buffer)

;; C-+/C-- zoom only the current buffer (same as C-mousewheel), C-0 reset.
;; C-= == C-+ (no shift needed).
(general-def 'global
  "C-+" #'text-scale-increase
  "C-=" #'text-scale-increase
  "C--" #'text-scale-decrease
  "C-0" (lambda () (interactive) (text-scale-set 0)))
;; t C-e exit terminal mode -> emacs/normal (nvim <C-\><C-n>)
(with-eval-after-load 'eat
  (general-def eat-semi-char-mode-map "C-e" #'eat-emacs-mode)
  (general-def eat-char-mode-map "C-e" #'eat-emacs-mode))
;; open terminals typeable (insert state) instead of evil-normal
(add-hook 'eat-mode-hook #'evil-insert-state)

;; macros: M-q == @
(general-nmap "M-q" #'my/run-macro)

;; window resize C-h/j/k/l set in evil-setup.

;; quickfix / trouble navigation
(general-nmap
  "C-n"   #'flymake-goto-next-error
  "C-S-n" #'flymake-goto-prev-error
  "C-t"   #'flymake-goto-next-error
  "C-S-t" #'flymake-goto-prev-error)

;; tabs + terminal (nvim M- maps). NOTE: M-x is rebound to tab-close to match
;; nvim; reach M-x's command palette via SPC : or `:` ex.
(general-def 'global
  "M-t" #'my/eat-tab
  "M-x" #'tab-bar-close-tab
  "M-c" #'tab-bar-new-tab
  "M-1" (lambda () (interactive) (tab-bar-select-tab 1))
  "M-2" (lambda () (interactive) (tab-bar-select-tab 2))
  "M-3" (lambda () (interactive) (tab-bar-select-tab 3))
  "M-4" (lambda () (interactive) (tab-bar-select-tab 4))
  "M-5" (lambda () (interactive) (tab-bar-select-tab 5)))

;;;; SPC leader -------------------------------------------------------------

(general-create-definer my/leader
  :states '(normal visual)
  :keymaps 'override
  :prefix "SPC")

(my/leader
  ;; commenting (gcc / gvgc)
  "x" #'evil-commentary-line

  ;; compile (compile-mode.nvim)
  "m" #'compile

  ;; window swap/move (winshift)
  "w" #'ace-window

  ;; venn -> artist box drawing
  "v" #'artist-mode

  ;; undotree
  "u" #'vundo

  ;; import.nvim -> jump to symbol (closest)
  "i" #'consult-imenu

  ;; popouts
  "e" #'treemacs                       ; neotree toggle
  "g" #'magit-status                   ; fugitive G
  "o" #'dirvish                        ; oil float
  "t" #'consult-flymake                ; trouble diagnostics

  ;; spectre (search/replace); seeds with symbol at point (== nvim s + sw)
  "s" (lambda () (interactive)
        (let ((sym (thing-at-point 'symbol t)))
          (if sym (query-replace sym (read-string (format "Replace %s with: " sym)))
            (call-interactively #'query-replace))))

  ;; telescope: find
  "ff" #'my/find-files
  "fc" #'my/find-files-dotfiles
  "fw" #'consult-ripgrep
  "fb" #'consult-buffer
  "f*" #'my/grep-string

  ;; lsp
  "le" #'consult-flymake
  "lf" #'xref-find-references
  "ld" #'xref-find-definitions
  "li" #'eldoc-box-help-at-point
  "lo" #'flymake-show-buffer-diagnostics
  "la" #'eglot-code-actions
  "ln" #'flymake-goto-next-error
  "lr" #'eglot-rename

  ;; debugging (dap -> dape)
  "dt" #'dape-info
  "b"  #'dape-breakpoint-toggle
  "B"  #'dape-breakpoint-expression

  ;; persp workspaces (Doom SPC TAB): create/switch/cycle/kill project layouts
  "TAB TAB" #'persp-switch
  "TAB n"   #'persp-next
  "TAB p"   #'persp-prev
  "TAB d"   #'persp-kill
  "TAB r"   #'persp-rename
  "TAB b"   #'persp-switch-to-buffer*
  "TAB s"   #'persp-state-save
  "TAB l"   #'persp-state-load

  ;; harpoon
  "a" #'harpoon-add-file
  "h" #'harpoon-toggle-quick-menu
  "1" #'harpoon-go-to-1
  "2" #'harpoon-go-to-2
  "3" #'harpoon-go-to-3
  "4" #'harpoon-go-to-4
  "5" #'harpoon-go-to-5

  ;; http requests (kulala -> restclient): rs send, ra send-all, rb scratchpad
  "rs" #'restclient-http-send-current
  "ra" #'restclient-http-send-current-stay-in-window
  "rb" #'restclient-mode

  ;; command palette fallback (since M-x is rebound)
  ":" #'execute-extended-command)

;;;; dashboard (snacks landing-page keys) -----------------------------------

(with-eval-after-load 'dashboard
  (general-def 'normal dashboard-mode-map
    "f" #'my/find-files
    "g" #'consult-ripgrep
    "r" #'consult-recent-file
    "p" #'project-switch-project
    "n" #'evil-buffer-new
    "q" #'save-buffers-kill-terminal))

;;;; debugging function keys (dape) -----------------------------------------

(general-def 'global
  "<f5>"  #'dape-continue
  "<f10>" #'dape-next
  "<f11>" #'dape-step-in
  "<f12>" #'dape-step-out)

(provide 'keys)
;;; keys.el ends here
