;;; keys.el --- every keybinding -*- lexical-binding: t; -*-

;; mirrors nvim's mappings.lua, the lazy specs' `keys' and whichkey.lua: same key, action and which-key text

(use-package general
  :config (general-evil-setup t))

;;;; helpers -----------------------------------------------------------------

(defun my/find-files ()
  "telescope find_files: project files, else fd from the project root."
  (interactive)
  ;; a bare repo's container has no work tree, so project.el's git ls-files fails there
  (condition-case nil
      (if (project-current)
          (project-find-file)
        (consult-fd default-directory))
    (error (consult-fd (my/project-root)))))

(defun my/find-files-dotfiles ()
  "telescope find_files cwd=~/projects/arch-dotfiles."
  (interactive)
  (consult-fd "~/projects/arch-dotfiles/"))

(defun my/grep-string ()
  "telescope grep_string: ripgrep the symbol under the cursor."
  (interactive)
  (consult-ripgrep (my/project-root) (thing-at-point 'symbol t)))

(defun my/replace-symbol ()
  "grug-far with the word prefilled: replace the symbol under the cursor project-wide."
  (interactive)
  (if-let* ((sym (thing-at-point 'symbol t)))
      (project-query-replace-regexp (regexp-quote sym)
                                    (read-string (format "Replace %s with: " sym)))
    (call-interactively #'project-query-replace-regexp)))

(defun my/run-macro ()
  "nvim M-x: execute a macro from a register, like @."
  (interactive)
  (evil-execute-macro 1 (evil-get-register (read-char "@register: ") t)))

(defun my/quickfix-cycle (n)
  "Jump N items through the error list (compile, grep, xref results), wrapping at either end like nvim's C-n."
  (if-let* ((buf (ignore-errors (next-error-find-buffer))))
      (condition-case nil
          (next-error n)
        (error
         ;; restart from the other end of the list
         (with-current-buffer buf
           (goto-char (if (> n 0) (point-min) (point-max)))
           (when (derived-mode-p 'compilation-mode)
             (setq-local compilation-current-error (point-marker))))
         (next-error n)))
    (message "quickfix list is empty")))

(defun my/quickfix-next ()
  "nvim C-n."
  (interactive)
  (my/quickfix-cycle 1))

(defun my/quickfix-prev ()
  "nvim C-S-n."
  (interactive)
  (my/quickfix-cycle -1))

(defun my/zoom-reset ()
  "Undo C-+ / C--."
  (interactive)
  (text-scale-set 0))

(defun my/resize (fn n)
  "Window resize command calling FN with N, quiet when there is nothing to resize."
  (lambda () (interactive) (ignore-errors (funcall fn n))))

;; bare keys show command names in which-key, where a lambda reads "??": every command gets a name
(dotimes (i 5)
  (let ((n (1+ i)))
    (defalias (intern (format "my/tab-%d" n))
      (lambda () (interactive) (tab-bar-select-tab n))
      (format "Select tab-bar tab %d." n))))

(dolist (fn '(("window-widen"  enlarge-window-horizontally 5)
              ("window-narrow" shrink-window-horizontally  5)
              ("window-taller" enlarge-window              3)
              ("window-shorter" shrink-window              3)))
  (defalias (intern (format "my/%s" (car fn)))
    (my/resize (nth 1 fn) (nth 2 fn))
    (format "Resize the current window: %s by %d." (nth 1 fn) (nth 2 fn))))

(defun my/move-lines (count)
  "mini.move: move the line, or every line the visual selection touches, one line down (COUNT 1) or up (-1)."
  (let* ((visual (evil-visual-state-p))
         (first (line-number-at-pos (if visual (region-beginning) (point))))
         (last (if visual (line-number-at-pos (max (region-beginning) (1- (region-end)))) first))
         (col (current-column)))
    (when (if (> count 0) (< last (line-number-at-pos (point-max))) (> first 1))
      ;; evil's :m, which also carries a visual selection along
      (evil-move (save-excursion (goto-char (point-min)) (forward-line (1- first)) (point))
                 (save-excursion (goto-char (point-min)) (forward-line last) (point))
                 (if (> count 0) (1+ last) (- first 2)))
      (unless visual (move-to-column col)))))

(defun my/move-down ()
  "mini.move M-j."
  (interactive)
  (my/move-lines 1))

(defun my/move-up ()
  "mini.move M-k."
  (interactive)
  (my/move-lines -1))

(defun my/shift-left ()
  "mini.move M-h in visual: dedent the selection and keep it."
  (interactive)
  (evil-shift-left (region-beginning) (region-end)))

(defun my/shift-right ()
  "mini.move M-l in visual: indent the selection and keep it."
  (interactive)
  (evil-shift-right (region-beginning) (region-end)))

(defun my/copy-mode ()
  "tmux copy-mode: stop typing into the terminal and navigate with vim keys."
  (interactive)
  (if (derived-mode-p 'eat-mode)
      (eat-emacs-mode)
    (evil-normal-state)))

(defun my/toggle-diagnostic-lines ()
  "nvim SPC lv: toggle inline end-of-line flymake diagnostics."
  (interactive)
  (setq flymake-show-diagnostics-at-end-of-line
        (not flymake-show-diagnostics-at-end-of-line))
  (when (bound-and-true-p flymake-mode) (flymake-mode 1))
  (message "flymake inline diagnostics %s" (if flymake-show-diagnostics-at-end-of-line "on" "off")))

(defun my/claude-toggle ()
  "nvim SPC c c: toggle the Claude window, starting it if none exists."
  (interactive)
  ;; deferred behind eat, load before calling its private fn
  (require 'claude-code)
  (if (claude-code--find-all-claude-buffers)
      (claude-code-toggle)
    (call-interactively #'claude-code)))

(defun my/claude-focus ()
  "nvim SPC c f: focus the Claude window."
  (interactive)
  (require 'claude-code)
  (call-interactively #'claude-code-switch-to-buffer))

(defun my/claude-send-region ()
  "nvim SPC c s: send the active region to Claude."
  (interactive)
  (require 'claude-code)
  (call-interactively #'claude-code-send-region))

(defun my/claude-send-buffer-file ()
  "nvim SPC c b: add the current buffer file to Claude."
  (interactive)
  (require 'claude-code)
  (call-interactively #'claude-code-send-buffer-file))

(defun my/eglot-code-actions ()
  "nvim SPC l a: LSP code actions."
  (interactive)
  (require 'eglot)
  (call-interactively #'eglot-code-actions))

(defun my/eglot-rename ()
  "nvim SPC l r: LSP rename."
  (interactive)
  (require 'eglot)
  (call-interactively #'eglot-rename))

(defconst my/import-prefixes
  '(((python-mode python-ts-mode) ("py") "import " "from ")
    ((rust-mode rust-ts-mode) ("rust") "use ")
    ((js-mode js-ts-mode typescript-ts-mode tsx-ts-mode) ("js" "ts") "import ")
    ((c-mode c-ts-mode c++-mode c++-ts-mode) ("c" "cpp") "#include "))
  "Per major modes: ripgrep file types, then the line prefixes that start an import.")

(defun my/import-pick ()
  "import.nvim SPC i: pick an import already used somewhere in the project and add it here."
  (interactive)
  (pcase-let* ((`(,_ ,types . ,prefixes)
                (or (seq-find (lambda (spec) (apply #'derived-mode-p (car spec))) my/import-prefixes)
                    (user-error "No import syntax known for %s" major-mode)))
               (regexp (concat "^" (regexp-opt prefixes)))
               (lines (apply #'process-lines-ignore-status "rg" "--no-filename" "--no-line-number" "--no-heading"
                             (append (mapcan (lambda (type) (list "-t" type)) (copy-sequence types))
                                     (list (concat "^(" (mapconcat #'regexp-quote prefixes "|") ")")
                                           (my/project-root)))))
               (pick (completing-read "Import: " (delete-dups lines) nil t)))
    (save-excursion
      (goto-char (point-max))
      (if (re-search-backward regexp nil t)
          (forward-line 1)
        (goto-char (point-min)))
      (insert pick "\n"))))

(defun my/comment-box (beg end)
  "comment-box.nvim SPC C b: box the selection, or the current line."
  (interactive (if (use-region-p)
                   (list (region-beginning) (region-end))
                 (list (line-beginning-position) (line-end-position))))
  (comment-box beg end))

(defun my/comment-separator ()
  "comment-box.nvim SPC C l: a commented separator line below, out to `fill-column'."
  (interactive)
  (end-of-line)
  (newline-and-indent)
  (let ((beg (point)))
    (insert (make-string (max 3 (- fill-column (current-column) (length comment-start) 1)) ?-))
    (comment-region beg (point))))

(defun my/jupyter-eval-line ()
  "molten SPC j l: evaluate the current line."
  (interactive)
  (code-cells-eval (line-beginning-position) (line-end-position)))

(defun my/jupyter-show-output ()
  "molten SPC j o: show the kernel's output."
  (interactive)
  (display-buffer (or (python-shell-get-buffer) (user-error "No kernel, SPC j i starts one"))))

(defun my/jupyter-hide-output ()
  "molten SPC j h: hide the kernel's output."
  (interactive)
  (when-let* ((buf (python-shell-get-buffer))
              (win (get-buffer-window buf)))
    (quit-window nil win)))

;; named, for the same which-key reason as the tab and resize commands above
(dolist (program '("gh-dash" "btop" "taskwarrior-tui"))
  (defalias (intern (format "my/popup-%s" program))
    (my/eat-popup-command program)
    (format "Toggle %s in a bottom popup." program)))

;;;; tmux layer: C-q ---------------------------------------------------------

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
  "w" #'my/project-pick                 ; bind w display-popup -E "tms"

  ;; windows
  "c" #'tab-bar-new-tab                 ; tmux default: prefix c
  "x" #'tab-bar-close-tab               ; bind x kill-window
  "]" #'tab-bar-switch-to-next-tab      ; n/p are popups, as in tmux/herdr
  "[" #'tab-bar-switch-to-prev-tab
  "1" #'my/tab-1
  "2" #'my/tab-2
  "3" #'my/tab-3
  "4" #'my/tab-4
  "5" #'my/tab-5

  ;; popups
  "g" #'my/popup-gh-dash                ; bind g display-popup -E "gh-dash"
  "p" #'my/popup-btop                   ; bind p display-popup -E "btop"
  "t" #'my/popup-taskwarrior-tui        ; bind t display-popup -E "taskwarrior-tui"
  "z" #'my/eat-popup                    ; bind z display-popup -E "zsh"
  "e" #'my/copy-mode)                   ; bind e copy-mode

;; move focus, no prefix
(general-define-key
 :states '(normal insert visual motion emacs)
 :keymaps 'override
 "M-H" #'windmove-left
 "M-J" #'windmove-down
 "M-K" #'windmove-up
 "M-L" #'windmove-right)

;;;; nvim layer: bare maps -----------------------------------------------------

(general-def 'global "C-s" #'save-buffer)
(general-imap "C-c" #'evil-normal-state)
(general-imap "C-SPC" #'completion-at-point)   ; blink.cmp show
(general-nmap "<escape>" #'evil-ex-nohighlight)

;; zoom the current buffer only
(general-def 'global
  "C-+" #'text-scale-increase
  "C-=" #'text-scale-increase
  "C--" #'text-scale-decrease
  "C-0" #'my/zoom-reset)

(general-nmap
  "C-h" #'my/window-narrow
  "C-l" #'my/window-widen
  "C-j" #'my/window-shorter
  "C-k" #'my/window-taller)

;; C-n walks the quickfix list (compile, grep, xref results), C-t the trouble list (diagnostics, wrapping)
(general-nmap
  "C-n"   #'my/quickfix-next
  "C-S-n" #'my/quickfix-prev
  "C-t"   #'flymake-goto-next-error
  "C-S-t" #'flymake-goto-prev-error)

;; nvim swapped them: M-q closes the tab, M-x replays a macro (normal state only, SPC : is M-x)
(general-nmap "M-x" #'my/run-macro)
;; override map: prog-mode's M-q (fill) and other mode maps must not shadow the tab keys
(general-define-key
  :states '(normal insert visual motion emacs)
  :keymaps 'override
  "M-t" #'my/eat-popup                  ; Snacks.terminal.toggle
  "M-w" #'kill-current-buffer           ; Snacks.bufdelete: the window stays
  "M-q" #'tab-bar-close-tab
  "M-c" #'tab-bar-new-tab
  "M-1" #'my/tab-1
  "M-2" #'my/tab-2
  "M-3" #'my/tab-3
  "M-4" #'my/tab-4
  "M-5" #'my/tab-5)

;; barbar <Tab>/<S-Tab>: <tab> is the key, so C-i still jumps forward; modes that fold on TAB keep it
(general-nmap
  :predicate '(not (derived-mode-p 'org-mode 'markdown-mode 'dired-mode))
  "<tab>"     #'next-buffer
  "<backtab>" #'previous-buffer)
(setq switch-to-prev-buffer-skip-regexp "\\`[ *]")   ; cycle files, not *Messages* and friends

;; mode maps such as dired's `m` still win
(general-nmap "m" #'compile)

;; flash.nvim s, vim-visual-multi M-d, mini.move M-hjkl, mini.align ga
(general-def '(normal visual) "s" #'evil-avy-goto-char-timer)
(general-nmap "M-d" #'evil-multiedit-match-symbol-and-next)
(general-vmap "M-d" #'evil-multiedit-match-and-next)
(general-nmap
  "M-j" #'my/move-down
  "M-k" #'my/move-up)
(general-vmap
  "M-j" #'my/move-down
  "M-k" #'my/move-up
  "M-h" #'my/shift-left
  "M-l" #'my/shift-right
  "ga"  #'align-regexp)

(general-nmap "zg" #'my/spell-add-word)          ; z= and ]s [s are evil's own

(general-def 'global
  "<f5>"  #'my/dap-continue
  "<f10>" #'dap-next
  "<f11>" #'dap-step-in
  "<f12>" #'dap-step-out)

;;;; nvim layer: SPC leader ----------------------------------------------------

(general-create-definer my/leader
  :states '(normal visual)
  :keymaps 'override
  :prefix "SPC")

(my/leader
  "x" '(evil-commentary-line :which-key "Comment line")
  ":" '(execute-extended-command :which-key "M-x")
  "w" '(ace-swap-window :which-key "Move window (WinShift)")
  "u" '(vundo :which-key "Undotree")
  "i" '(my/import-pick :which-key "Import")
  "v" '(artist-mode :which-key "Toggle venn (draw boxes)")
  "E" '(emmet-wrap-with-markup :which-key "Emmet wrap with abbreviation")
  "e" '(dirvish-side :which-key "File explorer (snacks)")
  "O" '(dirvish :which-key "Oil file manager (float)")
  "b" '(dap-breakpoint-toggle :which-key "Toggle breakpoint")
  "B" '(dap-breakpoint-condition :which-key "Conditional breakpoint")

  ;; harpoon
  "a" '(harpoon-add-file :which-key "Harpoon: add file")
  "h" '(harpoon-toggle-file :which-key "Harpoon: quick menu")
  "1" '(harpoon-go-to-1 :which-key "Harpoon: file 1")
  "2" '(harpoon-go-to-2 :which-key "Harpoon: file 2")
  "3" '(harpoon-go-to-3 :which-key "Harpoon: file 3")
  "4" '(harpoon-go-to-4 :which-key "Harpoon: file 4")
  "5" '(harpoon-go-to-5 :which-key "Harpoon: file 5")

  "f"  '(:ignore t :which-key "find")
  "ff" '(my/find-files :which-key "Find files")
  "fc" '(my/find-files-dotfiles :which-key "Find files (dotfiles)")
  "fw" '(consult-ripgrep :which-key "Live grep")
  "fb" '(consult-buffer :which-key "Buffers")
  "fr" '(consult-recent-file :which-key "Recent files")
  "f*" '(my/grep-string :which-key "Grep word under cursor")
  "fp" '(my/project-pick :which-key "Projects")

  "l"  '(:ignore t :which-key "lsp")
  "ld" '(xref-find-definitions :which-key "Go to definition")
  "lf" '(xref-find-references :which-key "LSP references")
  "li" '(eldoc-box-help-at-point :which-key "Hover info")
  "la" '(my/eglot-code-actions :which-key "Code action")
  "lr" '(my/eglot-rename :which-key "Rename symbol")
  "le" '(consult-flymake :which-key "Diagnostics (telescope)")
  "lo" '(my/diagnostic-at-point :which-key "Open diagnostic float")
  "ln" '(flymake-goto-next-error :which-key "Next diagnostic")
  "ls" '(consult-eglot-symbols :which-key "Workspace symbols")
  "lF" '(apheleia-format-buffer :which-key "Format buffer")
  "lv" '(my/toggle-diagnostic-lines :which-key "Toggle virtual_lines diagnostics")
  "lc" '(imenu-list-smart-toggle :which-key "Code outline (aerial)")
  "lp" '(my/math-preview :which-key "Math preview (popup)")
  "lP" '(prettify-symbols-mode :which-key "Math inline preview toggle")

  "t"  '(:ignore t :which-key "trouble")
  "tt" '(flymake-show-project-diagnostics :which-key "Trouble diagnostics")
  "ts" '(consult-imenu :which-key "Trouble symbols")
  "tl" '(xref-find-references :which-key "Trouble LSP references")

  "g"  '(:ignore t :which-key "git")
  "gg" '(magit-status :which-key "Lazygit")
  "gs" '(magit-status :which-key "Git (fugitive)")
  "gy" '(git-link :which-key "Open line on GitHub")
  "gd" '(magit-diff-working-tree :which-key "Diffview open")
  "gh" '(magit-log-buffer-file :which-key "File history (current file)")
  "gf" '(my/worktree-switch :which-key "Git worktrees")
  "gc" '(my/worktree-create :which-key "Git worktree for branch (switch or create)")

  "s"  '(:ignore t :which-key "search/replace")
  "ss" '(project-query-replace-regexp :which-key "Search/replace (grug-far)")
  "sw" '(my/replace-symbol :which-key "Search/replace word under cursor")

  ;; no accept/deny diff: claude-code.el has no mcp diff protocol
  "c"  '(:ignore t :which-key "claude")
  "cc" '(my/claude-toggle :which-key "Toggle Claude Code")
  "cf" '(my/claude-focus :which-key "Focus Claude")
  "cs" '(my/claude-send-region :which-key "Send selection to Claude")
  "cb" '(my/claude-send-buffer-file :which-key "Add current buffer to context")

  "d"  '(:ignore t :which-key "debug")
  "dt" '(my/dap-ui-toggle :which-key "Toggle DAP UI")

  "n"  '(:ignore t :which-key "test")
  "nr" '(my/test-nearest :which-key "Test nearest")
  "nf" '(my/test-file :which-key "Test file")
  "na" '(my/test-all :which-key "Test all")
  "nl" '(my/test-last :which-key "Test last")
  "no" '(my/test-output :which-key "Test output")
  "nx" '(my/test-stop :which-key "Test stop")

  "p"  '(:ignore t :which-key "profiling")
  "pf" '(my/perf-flamegraph :which-key "Perf flamegraph (flamelens)")
  "pg" '(my/perf-hotspot :which-key "Perf in hotspot (GUI)")
  "pc" '(my/perf-cargo-flamegraph :which-key "cargo flamegraph")
  "pr" '(my/perf-record :which-key "perf record a command")

  "j"  '(:ignore t :which-key "jupyter")
  "ji" '(run-python :which-key "Init kernel")
  "je" '(code-cells-eval :which-key "Evaluate operator")
  "jl" '(my/jupyter-eval-line :which-key "Evaluate line")
  "jv" '(code-cells-eval :which-key "Evaluate selection")
  "jr" '(code-cells-eval :which-key "Re-evaluate cell")
  "jo" '(my/jupyter-show-output :which-key "Show output")
  "jh" '(my/jupyter-hide-output :which-key "Hide output")
  "jn" '(code-cells-forward-cell :which-key "Next cell")
  "jp" '(code-cells-backward-cell :which-key "Previous cell")
  "jm" '(code-cells-eval-above :which-key "Evaluate cells above")

  "q"  '(:ignore t :which-key "session")
  "qs" '(my/session-restore :which-key "Restore session (cwd)")
  "ql" '(my/session-restore-last :which-key "Restore last session")
  "qd" '(my/session-stop :which-key "Stop saving session")

  "C"  '(:ignore t :which-key "comment/doc")
  "Cb" '(my/comment-box :which-key "Comment box (left)")
  "Cl" '(my/comment-separator :which-key "Comment separator line")

  "o"  '(:ignore t :which-key "github")
  "oi" '(my/gh-issues :which-key "List GitHub Issues")
  "op" '(my/gh-pulls :which-key "List GitHub PullRequests")
  "od" '(my/gh-discussions :which-key "List GitHub Discussions")
  "on" '(my/gh-notifications :which-key "List GitHub Notifications")
  "os" '(my/gh-search-repo :which-key "Search GitHub")
  "oR" '(my/gh-org-repos :which-key "List org repos")
  "oI" '(my/gh-org-issues :which-key "List org issues")
  "oP" '(my/gh-org-pulls :which-key "List org PRs")
  "oO" '(my/gh-org-search :which-key "Search org repos")

  "m"  '(:ignore t :which-key "orgmode")
  "ma" '(org-agenda :which-key "org agenda")
  "mc" '(org-capture :which-key "org capture"))

;; prefixes whose keys only exist once the package loads; without these which-key shows the raw key
(which-key-add-key-based-replacements
  "C-q" "tmux"        "gs" "surround")

;;;; package-local maps --------------------------------------------------------

;; gs prefix like nvim mini.surround; an `e` prefix kills the end-of-word motion
(with-eval-after-load 'evil-surround
  (evil-define-key '(normal visual) evil-surround-mode-map "gsa" #'evil-surround-region)
  (evil-define-key 'normal evil-surround-mode-map
    "gsd" #'evil-surround-delete
    "gsr" #'evil-surround-change))

;; C-a (telescope smart_send_to_qflist) and M-q export results to an editable wgrep buffer
(with-eval-after-load 'vertico
  (general-def vertico-map
    "C-j" #'vertico-next
    "C-k" #'vertico-previous
    "C-a" #'embark-export
    "M-q" #'embark-export))

(with-eval-after-load 'embark
  (general-def 'global
    "C-." #'embark-act
    "M-." #'embark-dwim))

;; blink.cmp keymap
(with-eval-after-load 'corfu
  (general-def corfu-map
    "C-SPC"     #'corfu-popupinfo-toggle
    "C-e"       #'corfu-quit
    "RET"       #'corfu-insert
    "TAB"       #'corfu-next
    "<tab>"     #'corfu-next
    "<backtab>" #'corfu-previous
    "C-b"       #'corfu-popupinfo-scroll-down
    "C-f"       #'corfu-popupinfo-scroll-up))

;; LuaSnip snippet_forward / snippet_backward
(with-eval-after-load 'tempel
  (general-def tempel-map
    "<tab>"     #'tempel-next
    "<backtab>" #'tempel-previous))

;; checkmate.nvim
(with-eval-after-load 'markdown-mode
  (evil-define-key 'normal markdown-mode-map (kbd "C-SPC") #'markdown-toggle-gfm-checkbox))

(with-eval-after-load 'dired
  (evil-define-key 'normal dired-mode-map
    "h" #'dired-up-directory
    "l" #'dired-find-file
    "q" #'quit-window
    (kbd "<backspace>") #'dired-up-directory
    (kbd "DEL")         #'dired-up-directory))

;; the sidebar: snacks explorer keys, over the dired ones above
(evil-define-key 'normal my/tree-mode-map
  "l"                 #'my/tree-open
  (kbd "RET")         #'my/tree-open
  (kbd "<return>")    #'my/tree-open
  "h"                 #'my/tree-close
  (kbd "<backspace>") #'dired-up-directory  ; explorer_up: re-root at the parent
  (kbd "DEL")         #'dired-up-directory
  "."                 #'dired-find-file     ; explorer_focus: re-root at the directory under the cursor
  "H"                 #'my/tree-toggle-hidden
  "a"                 #'my/tree-add
  "d"                 #'dired-do-delete
  "r"                 #'dired-do-rename
  "m"                 #'dired-do-rename
  "c"                 #'dired-do-copy
  "y"                 #'my/tree-yank-path
  "o"                 #'dired-do-open
  "u"                 #'revert-buffer
  "Z"                 #'dirvish-subtree-clear
  "q"                 #'dirvish-quit)

;; leave the terminal, like nvim's <C-\><C-n>
(with-eval-after-load 'eat
  (general-def eat-semi-char-mode-map "C-e" #'eat-emacs-mode)
  (general-def eat-char-mode-map      "C-e" #'eat-emacs-mode))

(provide 'keys)
;;; keys.el ends here
