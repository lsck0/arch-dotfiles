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

(defun my/eat-style ()
  "Pin eat to the UI font. The 16 ANSI colours follow the theme's themed
ansi-color-* faces (doom-themes-base), so eat matches the rest of the UI."
  (buffer-face-set :family my/font-family :height (* 10 my/font-size)))

; ; eat: pure elisp, no compilation step, good enough for a fallback setup.
(use-package eat
  :commands (eat eat-other-window)
  :config (setq eat-kill-buffer-on-exit t)
  ;; terminals open typeable, like tmux
  :hook ((eat-mode . evil-insert-state)
         (eat-mode . my/eat-style)))

(defun my/eat-tab ()
  "Open a shell in its own tab-bar tab, rooted at the project."
  (interactive)
  (require 'eat)
  (let ((default-directory (my/project-root)))
    (tab-bar-new-tab)
    ; ; ARG non-numeric = a fresh session, so every tab gets its own shell the ; way every tmux window does.
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
                    ; ; `eat-buffer-name' names it up front, so no renaming and ; no clash with the per-tab terminals above
                    (save-window-excursion
                      (let ((eat-buffer-name my/eat-popup-name))
                        (eat))))))
      (select-window (display-buffer buf))
      (evil-insert-state))))

; ;;; compile ----------------------------------------------------------------- ; compile-mode.nvim: `m` compiles, output opens below (see popups).

(setq compilation-scroll-output 'first-error
      compilation-always-kill t           ; never ask before restarting a build
      compilation-ask-about-save nil      ; save modified buffers silently
      compilation-max-output-line-length nil)

;; render build output colours instead of raw escape codes
(add-hook 'compilation-filter-hook #'ansi-color-compilation-filter)

; ;;; popups ------------------------------------------------------------------ ; Replaces the popper package: transient buffers get a dismissable bottom ; window instead of stealing a split.

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

; ; trim trailing whitespace only on lines actually edited, so it never ; pollutes a diff with unrelated churn
(use-package ws-butler
  :hook ((prog-mode . ws-butler-mode)
         (text-mode . ws-butler-mode)))

;;;; claude (claudecode.nvim) ------------------------------------------------

;; run Claude Code in an eat terminal, tied to the current project.
(use-package claude-code
  :vc (:url "https://github.com/stevemolitor/claude-code.el" :rev :newest)
  :after eat
  :config
  (setq claude-code-terminal-backend 'eat)
  (claude-code-mode 1))

;;;; debugging (nvim-dap) ----------------------------------------------------

(use-package dap-mode
  :commands (dap-debug dap-continue dap-breakpoint-toggle dap-breakpoint-condition
             dap-next dap-step-in dap-step-out)
  :config
  (require 'dap-ui)
  ;; native + python adapters (missing modules are skipped)
  (dolist (m '(dap-gdb-lldb dap-lldb dap-codelldb dap-python))
    (require m nil t))
  (setq dap-python-debugger 'debugpy)
  (dap-ui-mode 1)
  (dap-ui-controls-mode 1))

(defun my/dap-continue ()
  "nvim DapContinue: start a session if none is running, else continue."
  (interactive)
  (require 'dap-mode)
  (if (dap--cur-session) (dap-continue) (call-interactively #'dap-debug)))

(defun my/dap-ui-toggle ()
  "nvim dapui.toggle: show or hide the debugger windows."
  (interactive)
  (require 'dap-ui)
  (if (seq-find (lambda (w) (string-prefix-p "*dap-ui-" (buffer-name (window-buffer w))))
                (window-list))
      (dap-ui-hide-many-windows)
    (dap-ui-show-many-windows)))

;;;; testing (neotest core, via compile) -------------------------------------

;; per-mode test runner; nearest/summary/output/watch have no clean Emacs
;; equivalent (they need neotest's treesitter test detection).
(defvar my/test-commands
  '((python-ts-mode . "pytest") (python-mode . "pytest")
    (rust-ts-mode . "cargo nextest run") (rust-mode . "cargo nextest run"))
  "Major-mode to shell test runner for the compile-based test map.")

(defvar my/test-last-command nil "Last test command, reused by SPC n l.")

(defun my/test--runner ()
  (or (cdr (assq major-mode my/test-commands))
      (user-error "No test command for %s" major-mode)))

(defun my/test--run (cmd)
  (setq my/test-last-command cmd)
  (let ((default-directory (my/project-root))
        (compilation-buffer-name-function (lambda (_) "*test*")))
    (compile cmd)))

(defun my/test-all ()
  "neotest run all."
  (interactive) (my/test--run (my/test--runner)))

(defun my/test-file ()
  "neotest run file (per-file runners only; others run the whole suite)."
  (interactive)
  (my/test--run (if (derived-mode-p 'python-mode 'python-ts-mode)
                    (format "%s %s" (my/test--runner)
                            (shell-quote-argument (buffer-file-name)))
                  (my/test--runner))))

(defun my/test-last ()
  "neotest run last."
  (interactive) (my/test--run (or my/test-last-command (my/test--runner))))

(defun my/test-stop ()
  "neotest stop."
  (interactive) (kill-compilation))

;;;; profiling (perf flamegraphs) --------------------------------------------

(defvar my/perf-data-file "perf.data"
  "Default perf recording read by the profiling commands.")

(defun my/perf-flamegraph ()
  "nvim :Perf: perf.data -> collapsed stacks -> flamelens, in a terminal."
  (interactive)
  (require 'eat)
  (let* ((default-directory (my/project-root))
         (file (read-file-name "perf data: " nil my/perf-data-file t))
         (collapser (seq-find #'executable-find
                              '("stackcollapse-perf.pl" "inferno-collapse-perf")))
         (cmd (if collapser
                  (format "perf script -i %s | %s | flamelens"
                          (shell-quote-argument file) collapser)
                (format "flamelens %s" (shell-quote-argument file)))))
    (eat cmd t)))

(defun my/perf-hotspot ()
  "nvim :PerfGui: open perf.data in hotspot (GUI)."
  (interactive)
  (let ((default-directory (my/project-root)))
    (start-process "hotspot" nil "hotspot" my/perf-data-file)))

(defun my/perf-cargo-flamegraph (args)
  "nvim :CargoFlamegraph: cargo flamegraph in a terminal, writes flamegraph.svg."
  (interactive "sflamegraph args: ")
  (require 'eat)
  (let ((default-directory (my/project-root)))
    (eat (string-trim (concat "cargo flamegraph " args)) t)))

(defun my/perf-record (command)
  "nvim :PerfRecord: perf record -g COMMAND in a terminal, writes perf.data."
  (interactive "sperf record: ")
  (require 'eat)
  (let ((default-directory (my/project-root)))
    (eat (concat "perf record -g -- " command) t)))

(provide 'tools)
;;; tools.el ends here
