;;; keys.el --- every keybinding -*- lexical-binding: t; -*-

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

(defun my/toggle-diagnostic-lines ()
  "nvim SPC lv: toggle inline end-of-line flymake diagnostics."
  (interactive)
  (if (boundp 'flymake-show-diagnostics-at-end-of-line)
      (progn
        (setq flymake-show-diagnostics-at-end-of-line
              (not flymake-show-diagnostics-at-end-of-line))
        (when (bound-and-true-p flymake-mode) (flymake-mode 1))
        (message "flymake inline diagnostics %s"
                 (if flymake-show-diagnostics-at-end-of-line "on" "off")))
    (message "flymake-show-diagnostics-at-end-of-line unavailable (needs Emacs 30+)")))

(defun my/claude-toggle ()
  "nvim SPC c c: toggle the Claude window, starting it if none exists."
  (interactive)
  ;; claude-code is deferred (:after eat); load it before calling its private fn.
  (require 'claude-code)
  (if (claude-code--find-all-claude-buffers)
      (claude-code-toggle)
    (call-interactively #'claude-code)))

; ;;; ------------------------------------------------------------------------ ;;; tmux layer: C-q ;;; ------------------------------------------------------------------------ ; tmux "pane" -> Emacs window, tmux "window" -> tab-bar tab.

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

; ;;; ------------------------------------------------------------------------ ;;; nvim layer: bare maps ;;; ------------------------------------------------------------------------

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

; ; tabs + terminal.
(general-def 'global
  "M-t" #'my/eat-tab
  "M-x" #'tab-bar-close-tab
  "M-c" #'tab-bar-new-tab
  "M-1" (lambda () (interactive) (tab-bar-select-tab 1))
  "M-2" (lambda () (interactive) (tab-bar-select-tab 2))
  "M-3" (lambda () (interactive) (tab-bar-select-tab 3))
  "M-4" (lambda () (interactive) (tab-bar-select-tab 4))
  "M-5" (lambda () (interactive) (tab-bar-select-tab 5)))

; ; nvim binds bare `m` to compile-mode (not mark-set); mode maps such as ; dired's `m` still win, because they are more specific.
(general-nmap "m" #'compile)

;; nvim-dap function keys: continue/step, no prefix (nvim binds them in normal)
(general-def 'global
  "<f5>"  #'my/dap-continue
  "<f10>" #'dap-next
  "<f11>" #'dap-step-in
  "<f12>" #'dap-step-out)

; ;;; ------------------------------------------------------------------------ ;;; nvim layer: SPC leader ;;; ------------------------------------------------------------------------

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
  ;; g/t/s are prefixes (Emacs cannot make one key both a leaf and a prefix like
  ;; nvim does), so the primary action doubles the letter.
  "gg" #'magit-status                    ; nvim g: fugitive status
  "gy" #'git-link                        ; nvim gy: open line on remote
  "gh" #'magit-log-buffer-file           ; nvim gh: file history
  "gd" #'magit-diff-buffer-file          ; nvim gd: diff current file
  "tt" #'consult-flymake                 ; nvim t: trouble diagnostics
  "ts" #'consult-eglot-symbols           ; nvim ts: trouble symbols
  "tl" #'xref-find-references            ; nvim tl: trouble lsp references

  ; ; spectre.
  "ss" #'project-query-replace-regexp
  "sw" #'my/replace-symbol               ; nvim sw: replace word under cursor
  "S" #'my/replace-symbol

  ;; telescope
  "ff" #'my/find-files
  "fc" #'my/find-files-dotfiles
  "fw" #'consult-ripgrep
  "fb" #'consult-buffer
  "fr" #'consult-recent-file
  "f*" #'my/grep-string

  ;; claude (leader c in nvim). accept/deny diff have no equivalent: the
  ;; terminal claude-code.el has no MCP diff protocol, you accept in the TUI.
  "cc" #'my/claude-toggle                 ; toggle Claude Code
  "cf" #'claude-code-switch-to-buffer     ; focus Claude
  "cs" #'claude-code-send-region          ; send selection
  "cb" #'claude-code-send-buffer-file     ; add current buffer to context

  ;; debugging (nvim-dap)
  "dt" #'my/dap-ui-toggle                 ; toggle DAP UI
  "b"  #'dap-breakpoint-toggle            ; toggle breakpoint
  "B"  #'dap-breakpoint-condition         ; conditional breakpoint

  ;; testing (neotest). nearest/summary/output/watch need neotest: unbound.
  "na" #'my/test-all
  "nf" #'my/test-file
  "nl" #'my/test-last
  "nx" #'my/test-stop

  ;; profiling (perf flamegraphs)
  "pf" #'my/perf-flamegraph               ; flamelens
  "pg" #'my/perf-hotspot                  ; hotspot GUI
  "pc" #'my/perf-cargo-flamegraph         ; cargo flamegraph
  "pr" #'my/perf-record                   ; perf record -g

  ;; jupyter cells (leader j in nvim)
  "je" #'code-cells-eval
  "jn" #'code-cells-forward-cell
  "jp" #'code-cells-backward-cell
  "jm" #'code-cells-eval-above

  ;; lsp
  "ld" #'xref-find-definitions
  "lf" #'xref-find-references
  "li" #'eldoc-box-help-at-point
  "la" #'eglot-code-actions
  "lr" #'eglot-rename
  "le" #'consult-flymake
  "lo" #'flymake-show-buffer-diagnostics
  "ln" #'flymake-goto-next-error
  "ls" #'consult-eglot-symbols            ; nvim ls: workspace symbols
  "lF" #'apheleia-format-buffer           ; nvim lF: manual format
  "lv" #'my/toggle-diagnostic-lines)      ; nvim lv: toggle inline diagnostics

;; name the leader prefixes so which-key reads like nvim's whichkey groups
(which-key-add-key-based-replacements
  "SPC f" "find"      "SPC l" "lsp"    "SPC c" "claude"
  "SPC d" "debug"     "SPC n" "test"   "SPC p" "profiling"
  "SPC j" "jupyter"   "SPC t" "trouble"
  "SPC g" "git"       "SPC s" "search/replace")

; ;;; ------------------------------------------------------------------------ ;;; package-local maps ;;; ------------------------------------------------------------------------

;; Surround via evil-surround's own ys/ds/cs (normal) + S (visual). The old
;; ea/ed/er binds made `e` a prefix and killed the end-of-word motion.
(with-eval-after-load 'evil-surround
  (evil-define-key 'visual evil-surround-mode-map "S" 'evil-surround-region))

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

; ; oil.nvim movement inside dired.
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
