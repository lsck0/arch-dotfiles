;;; keys.el --- every keybinding -*- lexical-binding: t; -*-
;;
;; Two layers, so muscle memory from the real setup carries over:
;;
;;   C-q ...   the tmux prefix layer  (tmux.conf `set-option -g prefix C-q`)
;;   SPC ...   the nvim leader layer  (nvim lua/mappings.lua)
;;
;; plus the bare nvim maps (C-s, M-t, C-h/j/k/l, m, ...). Where tmux and nvim
;; disagree, both bindings are kept: they never collide.

(use-package general
  :config (general-evil-setup t))

;;;; helpers -----------------------------------------------------------------

(defun my/find-files ()
  "telescope find_files: project files, else fd from here."
  (interactive)
  (if (project-current)
      (project-find-file)
    (consult-fd default-directory)))

(defun my/find-files-dotfiles ()
  "telescope find_files cwd=~/projects/arch-dotfiles."
  (interactive)
  (consult-fd "~/projects/arch-dotfiles/"))

(defun my/grep-string ()
  "telescope grep_string: ripgrep the symbol under the cursor."
  (interactive)
  (consult-ripgrep (my/project-root) (thing-at-point 'symbol t)))

(defun my/replace-symbol ()
  "spectre with select_word: replace the symbol under the cursor project-wide."
  (interactive)
  (if-let* ((sym (thing-at-point 'symbol t)))
      (project-query-replace-regexp (regexp-quote sym)
                                    (read-string (format "Replace %s with: " sym)))
    (call-interactively #'project-query-replace-regexp)))

(defun my/run-macro ()
  "nvim M-q: execute a macro from a register."
  (interactive)
  (evil-execute-macro 1 (evil-get-register (read-char "@register: ") t)))

(defun my/zoom-reset ()
  "Undo C-+ / C--."
  (interactive)
  (text-scale-set 0))

(defun my/resize (fn n)
  "Window resize command calling FN with N, quiet when there is nothing to resize."
  (lambda () (interactive) (ignore-errors (funcall fn n))))

(defun my/copy-mode ()
  "tmux copy-mode: stop typing into the terminal and navigate with vim keys."
  (interactive)
  (if (derived-mode-p 'eat-mode)
      (eat-emacs-mode)
    (evil-normal-state)))

;;;; ------------------------------------------------------------------------
;;;; tmux layer: C-q
;;;; ------------------------------------------------------------------------
;; tmux "pane" -> Emacs window, tmux "window" -> tab-bar tab. The popups tmux
;; opens with external TUIs map to the Emacs equivalent of the same tool.

(defvar my/tmux-map (make-sparse-keymap)
  "Bindings under the tmux prefix C-q.")

(general-define-key
 :states '(normal insert visual motion emacs)
 :keymaps 'override
 "C-q" my/tmux-map)

(general-def my/tmux-map
  "C-q" #'quoted-insert                 ; bind-key C-q send-prefix

  ;; panes
  "v" #'evil-window-vsplit              ; bind v split-window -h
  "s" #'evil-window-split               ; bind s split-window -v
  "q" #'delete-window                   ; bind q kill-pane
  "o" #'delete-other-windows            ; tmux default: prefix z (zoom)
  "w" #'project-switch-project          ; bind w display-popup -E "tms"

  ;; windows
  "c" #'tab-bar-new-tab                 ; tmux default: prefix c
  "x" #'tab-bar-close-tab               ; bind x kill-window
  "n" #'tab-bar-switch-to-next-tab
  "p" #'tab-bar-switch-to-prev-tab
  "1" (lambda () (interactive) (tab-bar-select-tab 1))
  "2" (lambda () (interactive) (tab-bar-select-tab 2))
  "3" (lambda () (interactive) (tab-bar-select-tab 3))
  "4" (lambda () (interactive) (tab-bar-select-tab 4))
  "5" (lambda () (interactive) (tab-bar-select-tab 5))

  ;; popups
  "g" #'magit-status                    ; bind g display-popup -E "lazygit"
  "z" #'my/eat-popup                    ; bind z display-popup -E "zsh"
  "t" #'proced                          ; bind p display-popup -E "btop"
  "e" #'my/copy-mode)                   ; bind e copy-mode

;; bind -n M-H/J/K/L select-pane: move focus, no prefix needed
(general-define-key
 :states '(normal insert visual motion emacs)
 :keymaps 'override
 "M-H" #'windmove-left
 "M-J" #'windmove-down
 "M-K" #'windmove-up
 "M-L" #'windmove-right)

;;;; ------------------------------------------------------------------------
;;;; nvim layer: bare maps
;;;; ------------------------------------------------------------------------

;; C-s save, C-c leave insert, Esc clear search highlight
(general-def 'global "C-s" #'save-buffer)
(general-imap "C-c" #'evil-normal-state)
(general-nmap "<escape>" #'evil-ex-nohighlight)

;; neovide zoom: scale the current buffer only, C-0 resets
(general-def 'global
  "C-+" #'text-scale-increase
  "C-=" #'text-scale-increase
  "C--" #'text-scale-decrease
  "C-0" #'my/zoom-reset)

;; M-q == @ (run macro)
(general-nmap "M-q" #'my/run-macro)

;; smart-splits resize (tmux M-HJKL moves focus, these change size)
(general-nmap
  "C-h" (my/resize #'shrink-window-horizontally 5)
  "C-l" (my/resize #'enlarge-window-horizontally 5)
  "C-j" (my/resize #'shrink-window 3)
  "C-k" (my/resize #'enlarge-window 3))

;; quickfix / trouble navigation
(general-nmap
  "C-n"   #'flymake-goto-next-error
  "C-S-n" #'flymake-goto-prev-error
  "C-t"   #'flymake-goto-next-error
  "C-S-t" #'flymake-goto-prev-error)

;; tabs + terminal. NOTE: M-x is nvim's tabclose, so the command palette moved
;; to SPC : (and C-q is free of it entirely).
(general-def 'global
  "M-t" #'my/eat-tab
  "M-x" #'tab-bar-close-tab
  "M-c" #'tab-bar-new-tab
  "M-1" (lambda () (interactive) (tab-bar-select-tab 1))
  "M-2" (lambda () (interactive) (tab-bar-select-tab 2))
  "M-3" (lambda () (interactive) (tab-bar-select-tab 3))
  "M-4" (lambda () (interactive) (tab-bar-select-tab 4))
  "M-5" (lambda () (interactive) (tab-bar-select-tab 5)))

;; nvim binds bare `m` to compile-mode (not mark-set); mode maps such as
;; dired's `m` still win, because they are more specific.
(general-nmap "m" #'compile)

;;;; ------------------------------------------------------------------------
;;;; nvim layer: SPC leader
;;;; ------------------------------------------------------------------------

(general-create-definer my/leader
  :states '(normal visual)
  :keymaps 'override
  :prefix "SPC")

(my/leader
  "x" #'evil-commentary-line             ; gcc
  "m" #'recompile                        ; `m` compiles, SPC m re-runs it
  "w" #'ace-window                       ; WinShift
  "u" #'vundo                            ; undotree
  "i" #'consult-imenu                    ; jump to symbol
  ":" #'execute-extended-command         ; M-x, which nvim took for tabclose

  ;; popouts
  "e" #'dirvish-side                     ; neo-tree sidebar
  "o" #'dirvish                          ; oil, edit the directory as a buffer
  "g" #'magit-status                     ; fugitive
  "t" #'consult-flymake                  ; trouble

  ;; spectre. SPC s cannot be both a command and a prefix, so the
  ;; word-under-cursor variant (nvim SPC sw) is SPC S.
  "s" #'project-query-replace-regexp
  "S" #'my/replace-symbol

  ;; telescope
  "ff" #'my/find-files
  "fc" #'my/find-files-dotfiles
  "fw" #'consult-ripgrep
  "fb" #'consult-buffer
  "fr" #'consult-recent-file
  "f*" #'my/grep-string

  ;; lsp
  "ld" #'xref-find-definitions
  "lf" #'xref-find-references
  "li" #'eldoc-box-help-at-point
  "la" #'eglot-code-actions
  "lr" #'eglot-rename
  "le" #'consult-flymake
  "lo" #'flymake-show-buffer-diagnostics
  "ln" #'flymake-goto-next-error)

;;;; ------------------------------------------------------------------------
;;;; package-local maps
;;;; ------------------------------------------------------------------------

;; mini.surround: add / delete / replace. evil-surround's own ys/ds/cs stay live.
(with-eval-after-load 'evil-surround
  (evil-define-key 'normal evil-surround-mode-map
    "ea" 'evil-surround-region
    "ed" 'evil-surround-delete
    "er" 'evil-surround-change)
  (evil-define-key 'visual evil-surround-mode-map
    "ea" 'evil-surround-region))

;; telescope picker navigation; M-q sends results to an editable wgrep buffer
(with-eval-after-load 'vertico
  (general-def vertico-map
    "C-j" #'vertico-next
    "C-k" #'vertico-previous
    "M-q" #'embark-export))

;; telescope actions
(with-eval-after-load 'embark
  (general-def 'global
    "C-." #'embark-act
    "M-." #'embark-dwim))

;; nvim-cmp: C-SPC complete, C-e abort, CR confirm
(with-eval-after-load 'corfu
  (general-def corfu-map
    "C-SPC" #'completion-at-point
    "C-e"   #'corfu-quit
    "RET"   #'corfu-insert))

;; oil.nvim movement inside dired. Backspace goes up too, overriding dired's
;; own DEL (dired-unmark-backward); bind both spellings so it works in a GUI
;; frame and in -nw.
(with-eval-after-load 'dired
  (evil-define-key 'normal dired-mode-map
    "h" #'dired-up-directory
    "l" #'dired-find-file
    "q" #'quit-window
    (kbd "<backspace>") #'dired-up-directory
    (kbd "DEL")         #'dired-up-directory))

;; leave the terminal: C-e (nvim <C-\><C-n>) or C-q e (tmux copy-mode)
(with-eval-after-load 'eat
  (general-def eat-semi-char-mode-map "C-e" #'eat-emacs-mode)
  (general-def eat-char-mode-map      "C-e" #'eat-emacs-mode))

(provide 'keys)
;;; keys.el ends here
