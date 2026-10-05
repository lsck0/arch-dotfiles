;;; files-setup.el --- file browser -*- lexical-binding: t; -*-

;; sidebar = nvim's snacks explorer (tree in place, dotfiles + gitignored marked, H hides both); full dired = oil

(defconst my/tree-ignored-mark "\ue668"
  "Sidebar marker for gitignored entries: the nerd font seti-ignored glyph nvim's explorer shows.")

(defconst my/tree-hidden-mark "\U000F0209"
  "Sidebar marker for dotfiles that are not gitignored: nerd font md-eye_off, as in nvim.")

(defvar my/tree-hide nil
  "Non-nil after H in the sidebar: dotfiles and gitignored entries are omitted.")

(defvar-local my/tree-ignored-cache nil
  "Directory -> hash table of its gitignored entry names, rebuilt on every readin.")

(defun my/tree--ignored-names (dir)
  "Hash table of the names in DIR that git ignores; one `git check-ignore' per directory."
  (let ((table (make-hash-table :test #'equal))
        (default-directory dir)
        (names (directory-files dir nil directory-files-no-dot-files-regexp t)))
    (when names
      (with-temp-buffer
        ;; outside a repo git exits 128 and prints nothing on stdout, so the table stays empty
        (apply #'process-file "git" nil '(t nil) nil "check-ignore" "--" names)
        (dolist (name (split-string (buffer-string) "\n" t))
          (puthash (directory-file-name name) t table))))
    table))

(defun my/tree-state (file)
  "`ignored' when git ignores FILE, `hidden' for any other dotfile, else nil. Ignored wins over hidden."
  (let* ((dir (file-name-directory file))
         (name (file-name-nondirectory file))
         (cache (or my/tree-ignored-cache
                    (setq my/tree-ignored-cache (make-hash-table :test #'equal))))
         (ignored (or (gethash dir cache)
                      (puthash dir (my/tree--ignored-names dir) cache))))
    (cond ((gethash name ignored) 'ignored)
          ((string-prefix-p "." name) 'hidden))))

(defun my/tree--omit-regexp ()
  "Regexp for `dired-omit-files': every dotfile plus the names git ignores anywhere in the repo."
  (let ((ignored (ignore-errors
                   (process-lines "git" "ls-files" "--others" "--ignored" "--exclude-standard" "--directory"))))
    (concat "\\`\\."
            (when ignored
              (concat "\\|\\`"
                      (regexp-opt (delete-dups (mapcar (lambda (p) (file-name-nondirectory (directory-file-name p)))
                                                       ignored)))
                      "\\'")))))

(defun my/tree--apply-hide ()
  "Bring this sidebar buffer's `dired-omit-mode' in line with `my/tree-hide'."
  (unless (eq (bound-and-true-p dired-omit-mode) my/tree-hide)
    (require 'dired-x)
    (when my/tree-hide
      (setq-local dired-omit-files (my/tree--omit-regexp)
                  dired-omit-verbose nil))
    (dired-omit-mode (if my/tree-hide 1 -1))))

(defun my/tree-toggle-hidden ()
  "nvim explorer H: hide dotfiles and gitignored files together, or show both again."
  (interactive)
  (setq my/tree-hide (not my/tree-hide))
  (my/tree--apply-hide))

(defun my/tree--target-dir ()
  "Directory an action at point works in: the directory under the cursor, else the one holding the entry."
  (let ((file (dired-get-filename nil t)))
    (cond ((and file (file-directory-p file)) (file-name-as-directory file))
          (file (file-name-directory file))
          (t default-directory))))

(defun my/tree-open ()
  "nvim explorer l: expand or collapse the directory under the cursor, open a file in the main window."
  (interactive)
  (when-let* ((file (dired-get-filename nil t)))
    (if (file-directory-p file)
        (dirvish-subtree-toggle)
      (dired-find-file))))

(defun my/tree-close ()
  "nvim explorer h: collapse the directory under the cursor, else the one containing the entry."
  (interactive)
  (let ((file (dired-get-filename nil t)))
    (cond ((and file (file-directory-p file) (dirvish-subtree--expanded-p))
           (dirvish-subtree-toggle))
          ((dirvish-subtree--parent)
           (dirvish-subtree-up)
           (dirvish-subtree-toggle)))))

(defun my/tree-add (file)
  "nvim explorer a: create FILE, or a directory when the name ends in /."
  (interactive (list (read-file-name "Add (dir/ for a directory): " (my/tree--target-dir))))
  (if (directory-name-p file)
      (make-directory file t)
    (make-empty-file file t))
  (revert-buffer)
  (dirvish-subtree-expand-to (directory-file-name file)))

(defun my/tree-yank-path ()
  "nvim explorer y: copy the absolute path under the cursor."
  (interactive)
  (dired-copy-filename-as-kill 0))

(define-minor-mode my/tree-mode
  "Snacks explorer keys for the dirvish sidebar; bound in keys.el."
  :keymap (make-sparse-keymap)
  (evil-normalize-keymaps))

(use-package dirvish
  :init (dirvish-override-dired-mode 1)
  :config
  (setq dirvish-attributes '(nerd-icons file-size collapse subtree-state vc-state git-msg)
        ;; no size or commit message: the sidebar is 30 columns, as narrow as the nvim explorer
        dirvish-side-attributes '(nerd-icons collapse subtree-state vc-state tree-dim tree-mark)
        dirvish-use-header-line 'global
        dirvish-mode-line-format '(:left (sort symlink) :right (omit yank index))
        dirvish-side-width 30
        dirvish-side-window-parameters '((no-delete-other-windows . t))
        dirvish-quick-access-entries
        '(("h" "~/"                              "home")
          ("p" "~/projects/"                     "projects")
          ("c" "~/projects/arch-dotfiles/configs/" "configs")))

  ;; -v: version sort puts dotfiles first and file2 before file10; it compares bytes, so capitals sort before lowercase
  ;; --ignore=.git: nvim's explorer excludes **/.git, -I is not overridden by --almost-all
  (setq dired-listing-switches "-l --almost-all --human-readable --group-directories-first -v --ignore=.git"
        dired-dwim-target t                         ; other window = default target
        dired-recursive-copies 'always
        dired-recursive-deletes 'top
        dired-kill-when-opening-new-dired-buffer t  ; no buffer pileup
        delete-by-moving-to-trash t)

  (dirvish-define-attribute tree-dim
    "Dim dotfiles and gitignored files, like the snacks explorer."
    :when (not (dirvish-prop :remote))
    (when (my/tree-state f-name)
      (let ((ov (make-overlay f-beg f-end)))
        (overlay-put ov 'face 'dired-ignored)
        `(ov . ,ov))))

  (dirvish-define-attribute tree-mark
    "Right-aligned marker: gitignored first, then hidden."
    :when (not (dirvish-prop :remote))
    :width 2
    (when-let* ((state (my/tree-state f-name)))
      `(right . ,(propertize (if (eq state 'ignored) my/tree-ignored-mark my/tree-hidden-mark)
                             'face (or hl-face 'dired-ignored)))))

  ;; not `dirvish-side-follow-mode': it runs from `buffer-list-update-hook', which fires for any buffer that
  ;; merely becomes current -- a background process buffer, a `with-current-buffer' inside eglot or diff-hl --
  ;; and then re-roots the sidebar at that buffer's `default-directory'. Hence the jumping. Drive the follow
  ;; off the selected window instead, after a short debounce, and like lib/explorer.lua only ever reveal
  ;; inside the current root: a file elsewhere leaves the tree alone, SPC f p and SPC g f re-root it.
  (defvar my/dirvish-side-follow-timer nil)

  (defun my/dirvish-side-follow--now ()
    (setq my/dirvish-side-follow-timer nil)
    (when-let* ((win (ignore-errors (dirvish-side--session-visible-p)))
                (sel (selected-window))
                ((not (eq sel win)))
                ((not (window-minibuffer-p sel)))
                ((not (active-minibuffer-window)))
                (file (buffer-local-value 'buffer-file-name (window-buffer sel)))
                ((not (string-suffix-p "COMMIT_EDITMSG" file)))
                ((not (equal file (with-selected-window win (dirvish-prop :index)))))
                ((string-prefix-p (with-selected-window win (expand-file-name default-directory))
                                  (expand-file-name file))))
      (with-selected-window win
        (let (buffer-list-update-hook window-buffer-change-functions)
          (dirvish-winbuf-change-h win)
          (unwind-protect
              (if dirvish-side-auto-expand
                  (dirvish-subtree-expand-to file)
                (dired-goto-file file))
            (dirvish--redisplay))))))

  (defun my/dirvish-side-follow (&rest _)
    "Schedule a sidebar follow; coalesces the burst of hooks a window change fires."
    (unless my/dirvish-side-follow-timer
      (setq my/dirvish-side-follow-timer
            (run-with-idle-timer 0.1 nil #'my/dirvish-side-follow--now))))

  (remove-hook 'buffer-list-update-hook #'dirvish-side--auto-jump)
  (add-hook 'window-buffer-change-functions #'my/dirvish-side-follow)
  (add-hook 'window-selection-change-functions #'my/dirvish-side-follow)

  (defun my/dirvish-side-setup ()
    "Sidebar buffers: resizable, explorer keys, fresh gitignore data, the H state."
    (when-let* ((dv (dirvish-curr))
                ((eq (dv-type dv) 'side)))
      ;; :config is macroexpanded before dirvish loads, so nothing here may need the struct at
      ;; expansion time: `(setf (dv-size-fixed dv) ...)' becomes a call to the void
      ;; `(setf dv-size-fixed)', and `cl-struct-slot-value' inlines `(cl-typep dv 'dirvish)',
      ;; which falls back to calling the `dirvish' command on DV. Resolve the slot at runtime.
      (setf (aref dv (cl-struct-slot-offset 'dirvish 'size-fixed)) nil)
      (setq-local window-size-fixed nil
                  my/tree-ignored-cache nil)
      (unless my/tree-mode (my/tree-mode 1))
      (my/tree--apply-hide)))
  (add-hook 'dirvish-setup-hook #'my/dirvish-side-setup))

(defun my/tree-reroot (dir)
  "Show DIR as the root of the visible sidebar, if there is one."
  (when-let* (((fboundp 'dirvish-side--session-visible-p))
              (win (dirvish-side--session-visible-p)))
    (with-selected-window win
      (let (buffer-list-update-hook window-buffer-change-functions)
        (dirvish--find-entry 'find-alternate-file dir)))))

(defun my/startup-layout ()
  "A directory argument: cd into it and start on an empty buffer, no file browser (nvim's dir-arg); then the sidebar."
  ;; initial-buffer-choice shows *scratch* next to whatever the command line opened, in a second window
  (let ((dired (seq-find (lambda (buf) (with-current-buffer buf (derived-mode-p 'dired-mode)))
                         (mapcar #'window-buffer (window-list)))))
    (cond (dired
           (let ((dir (buffer-local-value 'default-directory dired)))
             (delete-other-windows)
             (switch-to-buffer (get-scratch-buffer-create))
             (setq default-directory dir)
             (kill-buffer dired)))
          ((cdr (window-list))
           (dolist (win (get-buffer-window-list (get-scratch-buffer-create)))
             (delete-window win)))))
  ;; focus stays in the main window
  (when (display-graphic-p)
    (save-selected-window (dirvish-side))))

(add-hook 'emacs-startup-hook #'my/startup-layout)

(provide 'files-setup)
;;; files-setup.el ends here
